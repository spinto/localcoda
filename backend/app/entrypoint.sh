#!/bin/bash

#Basic functions
function error(){
  echo "ERROR: $2"
  exit $1
}
for s in ip jq nginx ttyd mountpoint; do
  which $s &>/dev/null || error 2 "$s is required! Please install it"
done

#Load script options
[[ -z "$LOCALCODA_OPTIONS" ]] && error 3 "LOCALCODA_OPTIONS environment variable not found"
LOCALCODA_OPTIONS=( ${LOCALCODA_OPTIONS//,/ } )
INDEX_FILE="${LOCALCODA_OPTIONS[0]#/}"
EXT_PROTO="${LOCALCODA_OPTIONS[1]}"
EXT_EXITHOST="${LOCALCODA_OPTIONS[2]}"
EXT_MAINHOST="${LOCALCODA_OPTIONS[3]}"
EXT_PROXYHOST="${LOCALCODA_OPTIONS[4]}"
MAXTIME="${LOCALCODA_OPTIONS[5]}"
CLOSE_ON_EXIT="${LOCALCODA_OPTIONS[6]}"
[[ -z "$INDEX_FILE" ]] && error 3 "INDEX_FILE option empty" #tutorial to run: e.g. mlops/index.json
[[ -z "$EXT_EXITHOST" ]] && error 3 "EXT_EXITHOST option empty" #frontend host scheme: e.g. app.localcoda.com
[[ -z "$EXT_PROTO" ]] && error 3 "EXT_PROTO option empty" #external host scheme (for both main host and proxy host): e.g. http
[[ -z "$EXT_MAINHOST" ]] && error 3 "EXT_MAINHOST option empty" #backend host address: e.g. app-UUID.localcoda.com
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
  "ext_proxyhost":"$EXT_PROTO://$EXT_PROXYHOST",
  "exit_host":"$EXT_PROTO://$EXT_EXITHOST",
  "start_time": `date -u +%s`,
  "max_time": $MAXTIME
}
EOF

#Write localcoda host file (and killercoda one also, for cross-compatibility)
mkdir -p /etc/killercoda
echo "$EXT_PROTO://$EXT_PROXYHOST" > /etc/killercoda/host
echo "$EXT_PROTO://$EXT_PROXYHOST" > /etc/localcoda/host

#Logs folder
mkdir -p /var/log/localcoda/

#Detect if we are running in development mode (www is mounted). If so, we disable cache in nginx
mountpoint $WWW_DIR &>/dev/null && LOCALCODA_DEVELOPMENT_MODE_NGINX="# kill cachce for development mode
      add_header Last-Modified \$date_gmt;
      add_header Cache-Control 'no-store, no-cache';
      if_modified_since off;
      expires off;
      etag off;" || LOCALCODA_DEVELOPMENT_MODE_NGINX=

#Building nginx configuration
EXT_PROXYHOST_REGEX="${EXT_PROXYHOST/PORT/(?<redport>[0-9]+)}"
EXT_PROXYHOST_REGEX="${EXT_PROXYHOST_REGEX%:*}"
EXT_PROXYHOST_REGEX="~^${EXT_PROXYHOST_REGEX//./\.}$"
cat << EOF > /etc/localcoda/nginx.conf
user root;
worker_processes auto;
pid /etc/localcoda/nginx.pid;
error_log /var/log/localcoda/nginx_error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
  worker_connections 768;
}

http {
  sendfile on;
  tcp_nopush on;
  types_hash_max_size 2048;
  server_names_hash_bucket_size 128;

  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  access_log /var/log/localcoda/nginx_access.log;

  perl_modules /etc/localcoda;
  perl_require nginx-cmd.pm;


  map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
  }

  #Catch-all server for unspecified host
  server {
    listen      $EXT_LISTENPORT default_server;
    server_name "" "_";
    return      404;
  }
  server {
    listen $EXT_LISTENPORT;
    server_name "${EXT_MAINHOST%:*}";
    location /y/ {
      proxy_pass http://unix:/etc/localcoda/ttyd.sock;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
    }
    location /w/ {
      alias $WWW_DIR/;
      autoindex off;
    }
    location = /options.json {
      alias /etc/localcoda/www_options.json;
    }
    location /t {
      alias $TUTORIAL_DIR/;
      autoindex off;
      $LOCALCODA_DEVELOPMENT_MODE_NGINX
    }
    location = /c {
      perl cmd::handler;
    }
    location / {
      return 302 $EXT_PROTO://$EXT_MAINHOST/w/;
      add_header Access-Control-Allow-Origin *;
    }
    location = /favicon.ico {
      alias /etc/localcoda/www/favicon.ico;
    }
  }
  server {
    listen $EXT_LISTENPORT;
    server_name $EXT_PROXYHOST_REGEX;
    location / {
      proxy_pass http://127.0.0.1:\$redport;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_redirect off;
      proxy_buffering off;
      proxy_hide_header access-control-allow-origin;
      add_header Access-Control-Allow-Origin *;
    }
  }
}
EOF
cat << EOF > /etc/localcoda/nginx-cmd.pm
package cmd;

use nginx;
use strict;
use warnings;
use MIME::Base64;
use File::Temp qw(tempfile);
use IPC::Open3;
use Symbol 'gensym';

sub handler {
    my \$r = shift;

    if (\$r->request_method ne "POST") {
        return DECLINED;
    }

    if (\$r->has_request_body(\&post)) {
        return OK;
    }

    return HTTP_BAD_REQUEST;
}

sub post {
    my \$r = shift;

    # Sanitize file name from request body
    my \$cmd= join("/", map { (my \$p = \$_) =~ s/\s+/_/g; \$p =~ s/[^a-zA-Z0-9._-]//g; \$p } split /\//, \$r->request_body);
    return 400 if \$@ || !\$cmd;

    # Set the current directory
    chdir('$SCENARIO_DIR');

    # Check if command exists
    return 400 unless -e \$cmd;

    # Create a temporary file to grasp the exitcode
    # This is to avoid the exit code to be lost when the process is reaped automatically by perl
    my (\$fh, \$filename_exitcode) = tempfile(UNLINK => 1, SUFFIX => '.exitcode');
    close \$fh;
    unlink(\$filename_exitcode);

    # Execute the command
    my \$stderr = gensym;  # Create anonymous glob for stderr

    # Open3 returns pid of the child
    my \$interpreter='';
    if (!(-x \$cmd)) { \$interpreter='/bin/bash '; }
    my \$pid = open3(my \$stdin, my \$stdout, \$stderr, "/bin/bash -c '\$interpreter\$cmd; echo -n \\\$? > \$filename_exitcode'");

    close \$stdin;  # We're not sending anything to child stdin

    # Read stdout and stderr
    my \$out = <\$stdout>;
    my \$err = <\$stderr>;

    # Wait for the end
    waitpid(\$pid, 0);

    # Read the exit code from the file and delete the temporary file
    my \$exit_code;
    if (-e \$filename_exitcode) {
      open(my \$fh, '<', \$filename_exitcode);
      \$exit_code = <\$fh>;
      close(\$fh);
      unlink \$filename_exitcode;
    } else {
      \$exit_code = "-1";
    }

    # Encode output in base64
    my \$stdout_b64 = encode_base64(\$out // '', '');
    my \$stderr_b64 = encode_base64(\$err // '', '');

    # Manually build JSON (no escaping needed for base64 strings)
    my \$json = qq|{
  "exit_code": \$exit_code,
  "stdout_b64": "\$stdout_b64",
  "stderr_b64": "\$stderr_b64"
}|;

    # Return appropriate HTTP status
    \$r->status(\$exit_code == 0 ? 200 : 400);
    \$r->send_http_header('application/json');
    \$r->print(\$json);

    return OK;
}

1;
__END__
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

#All done. The webshell is now ready to accept connections. Exit correctly
touch /etc/localcoda/ready

#Start the webshell
if [[ "$CLOSE_ON_EXIT" == "true" ]]; then
  #Wait for the webshell to exit on disconnect, then poweroff
  ttyd -i /etc/localcoda/ttyd.sock -q -W -b /y /bin/bash $FOREGROUND_SCRIPT </dev/null &>/var/log/localcoda/webshell0.log
  poweroff
else
  #Just start the webshell (and replace this process with it
  exec ttyd -i /etc/localcoda/ttyd.sock -W -b /y /bin/bash $FOREGROUND_SCRIPT </dev/null &>/var/log/localcoda/webshell0.log
fi

#Exit with success
exit 0
