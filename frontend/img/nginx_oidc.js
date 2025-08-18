// /etc/nginx/oidc_introspection.js
//
// Full OIDC with Keycloak using:
//  - Authorization Code flow (redirect to login, callback exchanges code->tokens)
//  - Token introspection for validation (with short TTL cache)
//  - Logout -> revoke refresh token and clear cookies
//
// Requires: NGINX with njs (http_js_module) and outbound HTTP allowed to Keycloak.

// ======== CONFIG ========
const OIDC = {
  issuer:        'https://keycloak.example.com/realms/myrealm', // no trailing slash
  client_id:     'my-nginx-client',
  client_secret: 'MY-CLIENT-SECRET',
  // Must match Keycloak client's redirect URI
  redirect_uri:  'https://app.example.com/oidc/callback',

  // Cookie names
  cookie_access:  'OIDC_AT',   // access token (short-lived)
  cookie_refresh: 'OIDC_RT',   // refresh token (longer-lived)

  // Scopes for login
  scope: 'openid email profile',

  // Optional role to enforce (comment out to allow any authenticated user)
  required_role: 'admin',

  // Cache TTLs (ms)
  introspect_ttl_ms: 60000,     // 60s cache for introspection results
};

// Derived endpoints
const EP = {
  authorize:  `${OIDC.issuer}/protocol/openid-connect/auth`,
  token:      `${OIDC.issuer}/protocol/openid-connect/token`,
  introspect: `${OIDC.issuer}/protocol/openid-connect/token/introspect`,
  logout:     `${OIDC.issuer}/protocol/openid-connect/logout`,
};

// ======== SIMPLE LRU(ish) CACHE FOR INTROSPECTION ========
const cache = new Map(); // token -> { active, exp, username, email, roles, until }
function cacheGet(token) {
  const e = cache.get(token);
  if (!e) return null;
  if (Date.now() > e.until) { cache.delete(token); return null; }
  return e;
}
function cacheSet(token, value) {
  value.until = Date.now() + OIDC.introspect_ttl_ms;
  cache.set(token, value);
  // crude bound
  if (cache.size > 1000) {
    const firstKey = cache.keys().next().value;
    cache.delete(firstKey);
  }
}

// ======== HELPERS ========
function getCookie(r, name) {
  const raw = r.headersIn['Cookie'] || '';
  const m = raw.match(new RegExp(`${name}=([^;]+)`));
  return m ? decodeURIComponent(m[1]) : null;
}
function setCookie(r, name, value, opts = {}) {
  const parts = [`${name}=${encodeURIComponent(value)}`, 'Path=/'];
  if (opts.maxAge != null) parts.push(`Max-Age=${opts.maxAge}`);
  if (opts.sameSite) parts.push(`SameSite=${opts.sameSite}`);
  if (opts.httpOnly !== false) parts.push('HttpOnly');
  if (opts.secure !== false) parts.push('Secure');
  r.headersOut['Set-Cookie'] = (r.headersOut['Set-Cookie'] || []).concat(parts.join('; '));
}
function clearCookie(r, name) {
  setCookie(r, name, '', { maxAge: 0, sameSite: 'Lax' });
}
function urlEncode(obj) {
  return Object.entries(obj).map(([k,v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
}
function extractRolesFromIntrospection(introspectJson) {
  // Keycloak adds realm roles to `realm_access.roles` in ID/Access token.
  // Introspection response typically includes `scope`, sometimes `realm_access`.
  // We try both.
  if (introspectJson && introspectJson.realm_access && Array.isArray(introspectJson.realm_access.roles)) {
    return introspectJson.realm_access.roles;
  }
  // fallback: derive from `scope` if you map roles to scopes (optional)
  return [];
}

// ======== MAIN HANDLERS ========

// 1) /oidc/auth — gatekeeper for protected locations (used via auth_request)
// - If no valid AT, redirect to Keycloak login
// - If valid, 204 so NGINX lets request through
export async function auth(r) {
  try {
    let at = getCookie(r, OIDC.cookie_access);
    if (!at) {
      // no session -> redirect to login
      const loginUrl = `${EP.authorize}?` + urlEncode({
        client_id: OIDC.client_id,
        response_type: 'code',
        scope: OIDC.scope,
        redirect_uri: OIDC.redirect_uri,
      });
      r.return(302, loginUrl);
      return;
    }

    // Validate AT via cached introspection
    let entry = cacheGet(at);
    if (!entry) {
      const body = urlEncode({ token: at, client_id: OIDC.client_id, client_secret: OIDC.client_secret });
      const resp = await ngx.fetch(EP.introspect, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body
      });
      if (!resp.ok) {
        r.return(500, `Introspect error: ${resp.status}`);
        return;
      }
      const data = await resp.json();
      // RFC 7662: "active": boolean
      if (!data.active) {
        // Try refresh if we have RT
        const refreshed = await tryRefresh(r);
        if (!refreshed) {
          const loginUrl = `${EP.authorize}?` + urlEncode({
            client_id: OIDC.client_id, response_type: 'code', scope: OIDC.scope, redirect_uri: OIDC.redirect_uri,
          });
          r.return(302, loginUrl);
          return;
        }
        // refreshed -> new AT in cookie
        at = getCookie(r, OIDC.cookie_access);
        // re-introspect quickly
        const body2 = urlEncode({ token: at, client_id: OIDC.client_id, client_secret: OIDC.client_secret });
        const resp2 = await ngx.fetch(EP.introspect, {
          method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: body2
        });
        if (!resp2.ok) { r.return(500, `Introspect2 error: ${resp2.status}`); return; }
        const data2 = await resp2.json();
        if (!data2.active) { r.return(401, 'Unauthorized'); return; }
        entry = {
          active: true,
          exp: data2.exp || 0,
          username: data2.username || '',
          email: data2.email || '',
          roles: extractRolesFromIntrospection(data2),
        };
        cacheSet(at, entry);
      } else {
        entry = {
          active: true,
          exp: data.exp || 0,
          username: data.username || '',
          email: data.email || '',
          roles: extractRolesFromIntrospection(data),
        };
        cacheSet(at, entry);
      }
    }

    // Optional role check
    if (OIDC.required_role) {
      if (!entry.roles || !entry.roles.includes(OIDC.required_role)) {
        r.return(403, 'Forbidden');
        return;
      }
    }

    // Expose identity to upstream
    r.headersOut['X-User']  = entry.username || '';
    r.headersOut['X-Email'] = entry.email || '';
    r.return(204);
  } catch (e) {
    r.return(500, `auth error: ${e}`);
  }
}

// 2) /oidc/callback — exchanges code->tokens and sets cookies
export async function callback(r) {
  try {
    const code = r.args.code;
    if (!code) { r.return(400, 'Missing code'); return; }

    const body = urlEncode({
      grant_type: 'authorization_code',
      code,
      redirect_uri: OIDC.redirect_uri,
      client_id: OIDC.client_id,
      client_secret: OIDC.client_secret,
    });

    const resp = await ngx.fetch(EP.token, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });
    if (!resp.ok) { r.return(500, `Token exchange failed: ${resp.status}`); return; }

    const tok = await resp.json();
    // Set short-lived AT, longer RT. Let browser send them only to HTTPS.
    if (!tok.access_token) { r.return(500, 'No access token'); return; }
    setCookie(r, OIDC.cookie_access, tok.access_token, { sameSite: 'Lax' });

    if (tok.refresh_token) {
      // Typical Keycloak RT lifetime is longer; do NOT set Max-Age if you want session-only
      setCookie(r, OIDC.cookie_refresh, tok.refresh_token, { sameSite: 'Lax' });
    }

    // Redirect to original protected area (customize if you store/restore original URL)
    r.return(302, '/admin/');
  } catch (e) {
    r.return(500, `callback error: ${e}`);
  }
}

// 3) /oidc/logout — revokes refresh token and clears cookies
export async function logout(r) {
  try {
    const rt = getCookie(r, OIDC.cookie_refresh);
    clearCookie(r, OIDC.cookie_access);
    clearCookie(r, OIDC.cookie_refresh);

    if (rt) {
      const body = urlEncode({
        client_id: OIDC.client_id,
        client_secret: OIDC.client_secret,
        refresh_token: rt
      });
      // Keycloak logout endpoint accepts refresh_token
      await ngx.fetch(EP.logout, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body
      });
    }
    r.return(302, '/public/'); // Post-logout landing page
  } catch (_) {
    // Even if revoke fails, cookies are cleared -> treat as logged out
    r.return(302, '/public/');
  }
}

// ======== REFRESH FLOW ========
async function tryRefresh(r) {
  const rt = getCookie(r, OIDC.cookie_refresh);
  if (!rt) return false;

  const body = urlEncode({
    grant_type: 'refresh_token',
    refresh_token: rt,
    client_id: OIDC.client_id,
    client_secret: OIDC.client_secret,
  });

  const resp = await ngx.fetch(EP.token, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body
  });
  if (!resp.ok) return false;

  const tok = await resp.json();
  if (!tok.access_token) return false;

  // Overwrite cookies with fresh tokens
  setCookie(r, OIDC.cookie_access, tok.access_token, { sameSite: 'Lax' });
  if (tok.refresh_token) {
    setCookie(r, OIDC.cookie_refresh, tok.refresh_token, { sameSite: 'Lax' });
  }
  // Introspection cache will be repopulated on next check
  return true;
}

