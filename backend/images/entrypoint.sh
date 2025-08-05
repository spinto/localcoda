#!/bin/bash

#Basic functions
function error(){
  echo "ERROR: $2"
  exit $1
}
for s in ip jq nginx ttyd; do
  which $s &>/dev/null || error 2 "$s is required! Please install it"
done

#Load script options
[[ -z "$LOCALCODA_OPTIONS" ]] && error 3 "LOCALCODA_OPTIONS environment variable not found"
LOCALCODA_OPTIONS=( ${LOCALCODA_OPTIONS//,/ } )
INDEX_FILE="${LOCALCODA_OPTIONS[0]#/}"
INT_BASEPATH="${LOCALCODA_OPTIONS[1]}"
EXT_MAINHOST="${LOCALCODA_OPTIONS[2]}"
EXT_PROXYHOST="${LOCALCODA_OPTIONS[3]}"
MAXTIME="${LOCALCODA_OPTIONS[4]}"
CLOSE_ON_EXIT="${LOCALCODA_OPTIONS[5]}"
[[ -z "$INDEX_FILE" ]] && error 3 "INDEX_FILE option empty" #tutorial to run: e.g. mlops/index.json
[[ -z "$INT_BASEPATH" ]] && error 3 "INT_BASEPATH option empty" #base path to respond: e.g. /scenario/run/UUID/
[[ -z "$EXT_MAINHOST" ]] && error 3 "EXT_MAINHOST option empty" #external host address: e.g. app.localcoda.com
[[ -z "$EXT_PROXYHOST" ]] && error 3 "EXT_PROXYHOST option empty" #external proxy host address: e.g. app-PORT.localcoda.com
[[ -z "$MAXTIME" ]] && MAXTIME=3600
[[ -z "$CLOSE_ON_EXIT" ]] && CLOSE_ON_EXIT=true

#Hardcoded entrypoint paths. Ensure you have the same values in your backendconfiguration file
EXT_LISTENPORT="1"
WWW_DIR=/etc/localcoda/www
TUTORIAL_DIR=/etc/localcoda/tutorial
LOCAL_IPNET=172.30.1.2/24
SCENARIO_FILE="${TUTORIAL_DIR%/}/$INDEX_FILE"
SCENARIO_DIR="${SCENARIO_FILE%/*}"
[[ -f "$SCENARIO_FILE" ]] || error 1 "Invalid tutorial folder and/or index file path provded. No tutorial file found!"

#Setup dummy IP network (this is required by some tutorials)
ip link add localcoda0 type dummy && ip addr add $LOCAL_IPNET dev localcoda0 && ip link set localcoda0 up
[[ $? -ne 0 ]] && error "Failed to setup local ip network"

#Start image preparation script (if any)
if [[ -e /etc/localcoda/prepare_image.sh ]]; then
  echo "Preparing image..."
  /etc/localcoda/prepare_image.sh
  echo "Image is ready!"
fi

#Write options for web application
cat <<EOF > /etc/localcoda/www_options.json
{ 
  "index_file": "$INDEX_FILE",
  "ext_proxyhost":"http://$EXT_PROXYHOST",
  "start_time": `date -u +%s`,
  "max_time": $MAXTIME
}
EOF

#Write localcoda host file (and killercoda one also, for cross-compatibility)
mkdir -p /etc/killercoda
echo "http://$EXT_PROXYHOST" > /etc/killercoda/host
echo "http://$EXT_PROXYHOST" > /etc/localcoda/host

#Logs folder
mkdir -p /var/log/localcoda/

#Building nginx configuration
EXT_PROXYHOST_REGEX="~^${EXT_PROXYHOST/PORT/(?<redport>[0-9]+)}$"
EXT_PROXYHOST_REGEX="${EXT_PROXYHOST_REGEX//./\.}"
cat << EOF > /etc/localcoda/nginx.conf
user root;
worker_processes auto;
pid /etc/localcoda/nginx.pid;
error_log /var/log/localcoda/nginx_error.log;

events {
  worker_connections 768;
}

http {
  sendfile on;
  tcp_nopush on;
  types_hash_max_size 2048;
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  access_log /var/log/localcoda/nginx_access.log;

  #Catch-all server for unspecified host
  server {
    listen      $EXT_LISTENPORT default_server;
    server_name "" "_";
    return      404;
  }
  server {
    listen $EXT_LISTENPORT;
    server_name $EXT_MAINHOST;
    location $INT_BASEPATH/y/ {
      proxy_pass http://unix:/etc/localcoda/ttyd.sock;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "upgrade";
    }
    location $INT_BASEPATH/w/ {
      alias $WWW_DIR/;
      autoindex off;
    }
    location = $INT_BASEPATH/options.json {
      alias /etc/localcoda/www_options.json;
    }
    location $INT_BASEPATH/t {
      alias $TUTORIAL_DIR/;
      autoindex off;
    }
    location / {
      return 302 \$scheme://\$host$INT_BASEPATH/w/;
    }
    location = /favicon.ico {
      return 302 \$scheme://\$host$INT_BASEPATH/w/favicon.ico;
    }
  }
  server {
    listen $EXT_LISTENPORT;
    server_name $EXT_PROXYHOST_REGEX;
    location / {
      proxy_pass http://127.0.0.1:\$redport;
    }
  }
}
EOF

#Start nginx daemon
nginx -c /etc/localcoda/nginx.conf
[[ $? -ne 0 ]] && error 324 "Failed to start nginx"

#Copying assets (if any)
if [[ "`jq -r .details.assets.host01 < $SCENARIO_FILE`" != "null" ]]; then
  echo "Copying assets..."
  jq -r '.details.assets.host01[] | [.file, .target, .chmod] | @csv' < $SCENARIO_FILE | while read line; do
    v=( ${line//","/" "} )
    s="${v[0]#\"}";s="${s%\"}"
    d=${v[1]#\"};d="${d%\"}";d="${d%/}/"
    c="${v[2]#\"}";c="${c%\"}";
    mkdir -p "$d"
    [[ -d "$SCENARIO_DIR/assets/" ]] || error 34 "Scenario assets directory does not exist!"
    find "$SCENARIO_DIR/assets/" -name "$s" | while read f; do
      [[ ${f%/} == "$f" ]] || continue
      echo "  copy $f -> $d..."
      cp -r -L "$f" "$d"
      if [[ -n "$c" ]]; then
        of="${d%/*}/${f##*/}"
        echo "  chmod $c $of..."
        chmod $c "$of"
      fi
    done
  done
else
  echo "No assets to copy..."
fi

#Running background script in the background
INTRO_BACKGROUND="`jq -r .details.intro.background < $SCENARIO_FILE`"
if [[ -n "$INTRO_BACKGROUND" && "$INTRO_BACKGROUND" != "null" ]]; then
  BACKGROUND_FILE="`readlink -f "$SCENARIO_DIR/$INTRO_BACKGROUND"`"
  [[ -e "$BACKGROUND_FILE" ]] || error 12 "cannot access background file $BACKGROUND_FILE"
  echo "Starting background script $BACKGROUND_FILE, you can find its logs in /var/log/killercoda/"
	cd /root
  nohup bash -i -x $BACKGROUND_FILE 1>/var/log/localcoda/background0_stdout.log 2>/var/log/localcoda/background0_stderr.log &
else
  echo "No background script to run"
fi

#Start webshell
echo "Starting webshell..."
INTRO_FOREGROUND="`jq -r .details.intro.foreground < $SCENARIO_FILE`"
if [[ -n "$INTRO_FOREGROUND" && "$INTRO_FOREGROUND" != "null" && ! -e "/etc/localcoda/foreground_launcher.sh" ]]; then
  FOREGROUND_FILE="` readlink -f $SCENARIO_DIR/$INTRO_FOREGROUND`"
  [[ -e "$FOREGROUND_FILE" ]] || error 12 "cannot access foreground file $FOREGROUND_FILE"
	echo "Foreground script is $FOREGROUND_FILE."
  echo '[[ -e /etc/localcoda/foreground_launcher.sh.done ]] && exec bash -i' > /etc/localcoda/foreground_launcher.sh
  cat $FOREGROUND_FILE >> /etc/localcoda/foreground_launcher.sh
  echo -e '\ntouch /etc/localcoda/foreground_launcher.sh.done\nexec bash -i' >> /etc/localcoda/foreground_launcher.sh
  chmod +x /etc/localcoda/foreground_launcher.sh
  FOREGROUND_SCRIPT=/etc/localcoda/foreground_launcher.sh
else
  FOREGROUND_SCRIPT=""
fi

if [[ "$CLOSE_ON_EXIT" == "true" ]]; then
  #Wait for ttyd to terminate (which will do when all clients are disconnected), then poweroff
	cd /root
  ttyd -i /etc/localcoda/ttyd.sock -q -W -b $INT_BASEPATH/y /bin/bash $FOREGROUND_SCRIPT &>/var/log/localcoda/webshell0.log
  echo "no more ttyd connections. shutting down..."
  poweroff
else
  #Start in background then exit. Also, ttyd it should not terminate when all clients are disconnected.
  cd /root 
  nohup ttyd -i /etc/localcoda/ttyd.sock -W -b $INT_BASEPATH/y /bin/bash $FOREGROUND_SCRIPT &>/var/log/localcoda/webshell0.log &
fi

#Exit correctly (and write the ready file)
touch /etc/localcoda/ready
exit 0
