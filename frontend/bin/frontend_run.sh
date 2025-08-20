#/bin/bash
#Run for debug and test

#Basic functions
function error(){
  echo "ERROR: $2"
  exit $1
}
function check_sw(){
  for sw in $*; do
		which $sw &>/dev/null
    [[ $? -ne 0 ]] && error 2 "$sw not found in the PATH. This is required."
  done
}
function check_env(){
  for c in $*; do
    eval [[ -z "\$$c" ]] && error 3 "Configuration value of $c not set. Please set it in the $APPDIR/cfg/conf file!"
  done
}

#Check basic software is there
check_sw jq readlink grep

#Get app directory and load basic configuration
SWDIR="${BASH_SOURCE[0]}"
[[ "${SWDIR:0:1}" == "/" ]] || SWDIR="$PWD/$SWDIR"
cd "${SWDIR%/*}"; SWDIR="$PWD"
APPDIR="${SWDIR%/*}"
[[ -e "$APPDIR/../backend/cfg/conf" ]] || error 1 "Cannot find configuration file at $APPDIR/../backend/cfg/conf"
source $APPDIR/../backend/cfg/conf

#Load commandline options
APP_VERSION=0.0.1
function usage {
  cat <<:usage
localcoda frontend run version $APP_VERSION
Usage:
  frontend_run [options]

Options:
  -h             displays this help page
  -n <name>      Container/deployment name. Default is '$FRONTEND_NAME'
  -i <img>:<tag> Container image to run, including tag. Default is '$IMAGE_TORUN'. Use this to run a specific version of the frontend.
  -Kdn <n>       Deployment replicas (for Kubernetes deployment). Default is $KUBERNETES_FRONTEND_REPLICAS.
                 Increase this to serve more users.
  --auth <c>     Enable authentication and authorization using the internal oauth2-proxy installation. <c> points to the
                 oauth2-proxy provider configuration TOML file.
  -o <key>=<val> override the configuration option (in the $APPDIR/cfg/conf file). See
                 the content of the $APPDIR/cfg/conf file for specific options to override
  -Lp <ipport>   use <ipport> as loca orchestration engine ip/port for frontend. Default is $LOCAL_EXT_IPPORT.
                 NOTE: If you want to provide authentication, https, and redirect support you will need to install
                 an external proxy in front of this application.
  -Lt <dir>      use a local tutorial directory (only for local testing and using a local orchestrator)
  -Ldev          enable development mode. This will directly mount in read/write the frontend directories from
                 this repository instead of the ones in the image. Only for development and only for local orchestrator.
:usage
  exit 1
}

TUTORIAL_DIR=
FRONTEND_NAME="localcoda-frontend"
KUBERNETES_FRONTEND_REPLICAS=1
IMAGE_TORUN=spinto/localcoda-frontend:latest
LOCAL_EXT_IPPORT=0.0.0.0:80
LOCAL_DEV_MODE=false
OAUTH2_PROXY_CONF=
while [[ "$#" -gt 0 ]]; do
  case "$1" in
   -o) eval "$2"; shift 2 ;;
   -n) FRONTEND_NAME="$2"; shift 2 ;;
   -i) IMAGE_TORUN="$2"; shift 2 ;;
   -Lt) TUTORIAL_DIR="${2%/}"; shift 2 ;;
   -Lp) LOCAL_EXT_IPPORT="${2%/}"; shift 2 ;;
   -Ldev) LOCAL_DEV_MODE=true; shift 1 ;;
   -Kdn) KUBERNETES_FRONTEND_REPLICAS="$2"; shift 2 ;;
   --auth) OAUTH2_PROXY_CONF="`readlink -f $2`"; [[ -f "$OAUTH2_PROXY_CONF" ]] || error 33 "Auth proxy configuration does not exist or is not accessible. Try to use a valid absolute path!"; shift 2 ;;
   -h | --help) usage ;;
   *) error 1 "Unrecognized argument $1. See help!"
    ;;
  esac
done

#Check all general required variables are set
check_env EXT_DOMAIN_NAME EXT_FT_MAINHOST_SCHEME ORCHESTRATION_ENGINE TUTORIALS_VOLUME FRONTEND_NAME IMAGE_TORUN
#Hardcode tutorial volume access point, as we have this path always the same in the frontend
TUTORIALS_VOLUME_ACCESS_MOUNT=/data/tutorials

#Use the orchestration engine to run the backend instance
if [[ $ORCHESTRATION_ENGINE == "local" ]]; then
  check_sw docker
  check_env LOCAL_EXT_IPPORT

  #Check tutorials path or volume existence
  DOCKER_ARGS=
  if [[ -n "$TUTORIAL_DIR" ]]; then
    [[ -d "$TUTORIAL_DIR" ]] && error 33 "Specified tutorial directory does not exist!"
    DOCKER_ARGS="--mount type=bind,src=$TUTORIAL_DIR,dst=$TUTORIALS_VOLUME_ACCESS_MOUNT"
  else
    #Check if volume image exists
    docker volume inspect $TUTORIALS_VOLUME >/dev/null
    [[ $? -ne 0 ]] && error 32 "Docker volume does not exists. Please run backend initialization script in backend/bin/backend_init.sh or use a local tutorial directory via the -Lt switch"
    DOCKER_ARGS="--mount type=volume,src=$TUTORIALS_VOLUME,dst=$TUTORIALS_VOLUME_ACCESS_MOUNT,volume-nocopy"
  fi

  #Enable auth2 proxy authentication
  if [[ -n "$OAUTH2_PROXY_CONF" ]]; then
    [[ -f "$OAUTH2_PROXY_CONF" ]] || error 33 "Oauth proxy configuration does not exists"
    DOCKER_ARGS="$DOCKER_ARGS -v $OAUTH2_PROXY_CONF:/opt/localcoda/oauth2-proxy.cfg.base:ro"
  fi

  #Start the container in the background (we need to start this as root to access the docker daemon on the VM)
  echo "Starting frontend..."
  if $LOCAL_DEV_MODE; then
    echo "Running in local development mode. First thing you should do is to run the entrypoint via './entrypoint &'"
    docker run -u 0 -v /var/run/docker.sock:/var/run/docker.sock --name "$FRONTEND_NAME" $DOCKER_ARGS --network=host -e "LOCAL_EXT_IPPORT=$LOCAL_EXT_IPPORT" -v $APPDIR/app:/opt/app:ro -v $APPDIR/www:/opt/www:ro -v $APPDIR/../backend:/backend:ro --rm -it --entrypoint /bin/bash "$IMAGE_TORUN" -c 'cd /opt/localcoda; rm -rf *; ln -s ../www ../app/*.sh ./; cp -r ../app/backend ./; ln -s ../../../backend/cfg backend/; exec bash'
    [[ $? -ne 0 ]] && error 1 "Failed to start container"
  else
    docker run -u 0 -d --restart unless-stopped -v /var/run/docker.sock:/var/run/docker.sock --name "$FRONTEND_NAME" $DOCKER_ARGS --network=host -e "LOCAL_EXT_IPPORT=$LOCAL_EXT_IPPORT" -v $APPDIR/../backend/cfg:/opt/localcoda/backend/cfg:ro "$IMAGE_TORUN"
    [[ $? -ne 0 ]] && error 1 "Failed to start service"

    #Get frontend path
    if [[ "$EXT_DOMAIN_NAME" =~ NIP_ADDRESS ]]; then
      #Generate nip address hash
      NIP_ADDRESS="`hostname -I | awk '{split($1, a, "."); printf("%02x%02x%02x%02x.nip.io\n", a[1], a[2], a[3], a[4])}'`"
      eval EXT_DOMAIN_NAME=$EXT_DOMAIN_NAME
    fi
    eval EXT_FT_MAINHOST=$EXT_FT_MAINHOST_SCHEME
    echo "Your frontend has started and should be accessible from:
    http://$EXT_FT_MAINHOST/"
  fi

elif [[ $ORCHESTRATION_ENGINE == "kubernetes" ]]; then
  check_sw kubectl
  check_env KUBERNETES_NAMESPACE KUBERNETES_FRONTEND_REPLICAS

  #Tutorial dir is an option only for the local orchestrator
  [[ -n "$TUTORIAL_DIR" ]] && error 3 "You can use a local tutorial directory only for the local orchestrator"

  #Check tutorials volume existence
  kubectl -n "$KUBERNETES_NAMESPACE" get pvc $TUTORIALS_VOLUME >/dev/null
  [[ $? -ne 0 ]] && error 33 "$TUTORIALS_VOLUME does not exit. Please run backend initialization script in backend/bin/backend_init.sh."

  #Deploy service
  {
    cat << EOF
apiVersion: v1
kind: Deployment
metadata:
  name: $EXECUTION_NAME
  labels:
    localcoda: "frontend"
spec:
  replicas: $KUBERNETES_FRONTEND_REPLICAS
  selector:
    matchLabels:
      localcoda: "frontend"
  template:  
    metadata:
      labels:
        localcoda: "frontend"
    spec:
      containers:
      - name: app
        image: $IMAGE_TORUN
        ports:
        - containerPort: 80
        volumeMounts:
        - mountPath: /data/tutorials
          name: tutorials-path
        - mountPath: /opt/localcoda/cfg
          name: cfg-path
          readOnly: true
      volumes:
      - name: tutorials-path
        persistentVolumeClaim:
          claimName: $TUTORIALS_VOLUME
      - name: cfg-path
        configMap:
          name: $EXECUTION_NAME-cfg
---
apiVersion: v1
kind: Service
metadata:
  name: $EXECUTION_NAME
spec:
  selector:
    localcoda: "frontend"
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $EXECUTION_NAME
spec:
  ingressClassName: nginx
  rules:
  - host: "$EXT_MAINHOST"
    http:
      paths:
      - pathType: Prefix
        path: "$EXT_BASEPATH"
        backend:
          service:
            name: $EXECUTION_NAME
            port:
              number: 80
---
EOF
    kubectl create -n "$KUBERNETES_NAMESPACE" configmap $EXECUTION_NAME-cfg --from-file="$APPDIR/cfg" --dry-run -o yaml
  } | kubectl -n "$KUBERNETES_NAMESPACE" apply -f -
  [[ $? -ne 0 ]] && error 54 "Failed to start backend pod"

  #Wait for pod to be ready (if requested)
  echo "Waiting for $EXECUTION_NAME to start..."
  kubectl -n "$KUBERNETES_NAMESPACE" rollout status deployment/$EXECUTION_NAME --timeout=60s

  #Tutorial is started
  echo "Your tutorial is ready and accessible from:
    http://$EXT_MAINHOST$INT_BASEPATH 

NOTE: Do not forget to enable HTTPs and user support by following the instructions in the README file."

fi

#all done correctly if we are at this point
exit 0
