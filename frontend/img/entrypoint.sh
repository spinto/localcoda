#!/bin/bash
#Localcoda frontend start

function error(){
  echo $2 >&2
  exit $1
}

#Create run directories
mkdir -p /var/log/localcoda

#Start FastCGI wrapper
nohup fcgiwrap -p /opt/localcoda/cgiwrap.sh -c 3 -s unix:/opt/localcoda/cgiwrap.sock </dev/null 2>&1 | rotatelogs -n 30 /var/log/localcoda/fcgiwrap.log 86400 &
[[ $? -ne 0 ]] && error 1 "ERROR: failed to start fastcgi wrapper"
echo -n "$!" > /opt/localcoda/cgiwrap.pid

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
eval EXT_FT_MAINHOST=$EXT_FT_MAINHOST_SCHEME

#Local external IP port default
[[ -z "$LOCAL_EXT_IPPORT" ]] && LOCAL_EXT_IPPORT=0.0.0.0:80

cat <<EOF > /opt/localcoda/nginx.conf
user `id -u -n`;
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

    # Log files
    access_log /dev/stdout combined;
    error_log  /dev/stdout;

    server {
        listen $LOCAL_EXT_IPPORT;
        server_name $EXT_FT_MAINHOST;

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

server {

    listen $LOCAL_EXT_IPPORT;
    server_name ~-(?<redport>[0-9]+)\\.$EXT_DOMAIN_NAME\$;
    location / {
      proxy_pass http://127.0.0.1:\$redport;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
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
