#!/bin/bash
#Localcoda frontend start

function error(){
  echo $2 >&2
  exit $1
}

#Start FastCGI wrapper
nohup fcgiwrap -p /opt/localcoda/cgiwrap.sh -c 3 -s unix:/opt/localcoda/cgiwrap.sock </dev/null 2>&1 | rotatelogs -n 30 /var/log/localcoda/fcgiwrap.log 86400 &
[[ $? -ne 0 ]] && error 1 "ERROR: failed to start fastcgi wrapper"
echo -n "$!" > /opt/localcoda/fcgiwrap.pid

#Create nginx configuration
SWDIR="${BASH_SOURCE[0]}"
[[ "${SWDIR:0:1}" == "/" ]] || SWDIR="$PWD/$SWDIR"
cd "${SWDIR%/*}"; SWDIR="$PWD"
WWWDIR="$SWDIR/www"
[[ -e "$SWDIR/backend/cfg/conf" ]] || error 1 "Cannot find configuration file at $SWDIR/backend/cfg/conf"
source $SWDIR/backend/cfg/conf

#Hardcode tutorial volume access point, as we have this path always the same in the frontend
TUTORIALS_VOLUME_ACCESS_MOUNT=/data/tutorials

#Frontend host name
#Calculate external domain name (if required)
if [[ "$EXT_DOMAIN_NAME" =~ NIP_ADDRESS ]]; then
  #Generate nip address hash
  NIP_ADDRESS="`hostname -i | awk '{ for(i=1; i<=NF; i++){if($i !~ /^127\./){split($i,a,".");printf("%02x%02x%02x%02x.nip.io\n",a[1],a[2],a[3],a[4]);exit;}}}'`"
  eval EXT_DOMAIN_NAME=$EXT_DOMAIN_NAME
fi
eval EXT_FT_MAINHOST=$EXT_FT_MAINHOST_SCHEME

#Local external IP port default
[[ -z "$LOCAL_EXT_IPPORT" ]] && LOCAL_EXT_IPPORT=0.0.0.0:80

#Check if you need authentication via oauth proxy
if [[ -f "/opt/localcoda/oauth2-proxy.cfg.base" ]]; then
  #Create oauth2 proxy configuration file
  cat << EOF > /opt/localcoda/oauth2-proxy.cfg
http_address = "127.0.0.1:4180"
set_xauthrequest = true
reverse_proxy = true
cookie_secret = "$(openssl rand -base64 32 | head -c 32 | base64)"
cookie_secure = false
EOF
  cat /opt/localcoda/oauth2-proxy.cfg.base >> /opt/localcoda/oauth2-proxy.cfg
  #Run Oauth2 proxy
  nohup oauth2-proxy --config=/opt/localcoda/oauth2-proxy.cfg </dev/null 2>&1 | /usr/bin/rotatelogs -n 30 /var/log/localcoda/oauth2-proxy.log 86400 &
  [[ $? -ne 0 ]] && error 1 "ERROR: failed to start oauth2 proxy"
  echo -n "$!" > /opt/localcoda/oauth2-proxy.pid
fi

rm -f /opt/localcoda/nginx.conf
[[ "`id -nu`" == "root" ]] && echo 'user root;' >> /opt/localcoda/nginx.conf
cat <<EOF >> /opt/localcoda/nginx.conf
worker_processes auto;
pid /opt/localcoda/nginx.pid;

events {
  worker_connections 1024;
}

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  sendfile        on;
  keepalive_timeout  65;

  # Log files to stdout, which will go to rotatelogs
  access_log /dev/stdout combined;
  error_log  /dev/stdout;

  server {
    listen $LOCAL_EXT_IPPORT;
    server_name $EXT_FT_MAINHOST;

EOF
if [[ -f "/opt/localcoda/oauth2-proxy.cfg.base" ]]; then
  cat <<EOF >>/opt/localcoda/nginx.conf
    #Configuration for oauth2 proxy
    location /oauth2/ {
      proxy_pass       http://127.0.0.1:4180;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Auth-Request-Redirect \$request_uri;
    }
    location = /oauth2/auth {
      proxy_pass       http://127.0.0.1:4180;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-Uri \$request_uri;
      proxy_set_header Content-Length "";
      proxy_pass_request_body off;
    }
    location = /oauth2/sign_out {
      proxy_pass       http://127.0.0.1:4180;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-Uri \$request_uri;
    }
EOF
fi
cat <<EOF >>/opt/localcoda/nginx.conf
    # Serve a single CGI script for all /app/ requests
    location /ctl {
      gzip off;
      include /etc/nginx/fastcgi_params;
      fastcgi_pass unix:/opt/localcoda/cgiwrap.sock;

      # Always run the same CGI script
      fastcgi_param SCRIPT_FILENAME /opt/localcoda/cgiwrap.sh;

      # Pass the path to PATH_INFO
      fastcgi_param PATH_INFO \$uri;

      # Keep query string and request info intact
      fastcgi_param QUERY_STRING    \$query_string;
      fastcgi_param REQUEST_METHOD  \$request_method;
      fastcgi_param CONTENT_TYPE    \$content_type;
      fastcgi_param CONTENT_LENGTH  \$content_length;

      # Add localcoda specific application configuration
      fastcgi_param TUTORIALS_VOLUME_ACCESS_MOUNT $TUTORIALS_VOLUME_ACCESS_MOUNT;
EOF
if [[ -f "/opt/localcoda/oauth2-proxy.cfg.base" ]]; then
  cat <<EOF >>/opt/localcoda/nginx.conf

      # Authentication via oauth2-proxy
      auth_request /oauth2/auth;
      auth_request_set \$user \$upstream_http_x_auth_request_user;
      fastcgi_param X-USER \$user;
EOF
fi
cat <<EOF >>/opt/localcoda/nginx.conf
    }

    # Main application files
    location / {
      root /opt/localcoda/www;
      index index.html;
    }
  }
EOF
if [[ "$LOCAL_INT_F_PROXY" == "true" ]]; then
  #Install the internal proxy for the local installation
  cat <<EOF >> /opt/localcoda/nginx.conf
  map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
  }
  # Extract port from Host header if present
  map $http_host $forwarded_port {
      # Host includes a port → extract it
      ~^(?<h>[^:]+):(?<p>\d+)$  $p;
      # No port → choose default based on scheme
      default $scheme_default_port;
  }
  # Determine default port based on scheme
  map $scheme $scheme_default_port {
      http   80;
      https  443;
  }
  #Proxy for local deployment
  server {
    listen $LOCAL_EXT_IPPORT;
    server_name ~-(?<redport>[0-9]+)\\.$EXT_DOMAIN_NAME\$;
    location / {
      proxy_pass http://127.0.0.1:\$redport;
      proxy_set_header Host \$http_host;
      proxy_set_header X-Forwarded-Host \$http_host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Forwarded-Port \$forwarded_port;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header Host \$host;
      proxy_redirect off;
      proxy_buffering off;
      proxy_hide_header access-control-allow-origin;
      add_header Access-Control-Allow-Origin *;
    }
  }
EOF
fi
echo '}' >> /opt/localcoda/nginx.conf

exec nginx -c /opt/localcoda/nginx.conf | /usr/bin/rotatelogs -n 30 /var/log/localcoda/nginx.log 86400
