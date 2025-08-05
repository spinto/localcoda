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
check_sw readlink

#Get app directory and load basic configuration
SWDIR="`readlink -f "$0"`"; SWDIR="${SWDIR%/*}"
APPDIR="`readlink -f "${SWDIR%/*}"`"; APPDIR="${APPDIR%/}"
[[ -e "$APPDIR/cfg/conf" ]] || error 1 "Cannot find configuration file at $APPDIR/cfg/conf"
source $APPDIR/cfg/conf
TAPPDIR="`readlink -f "${APPDIR%/*}"`"; TAPPDIR="${TAPPDIR%/}/tutorials/data"
[[ -e "$TAPPDIR" ]] || error 1 "Cannot find tutorials dir at $TAPPDIR"
WWWDIR=`readlink -f $APPDIR/www`
[[ -e "$WWWDIR" ]] || error 1 "Cannot find www dir at $WWWDIR"

#Load commandline options
APP_VERSION=0.0.1
function usage {
  cat <<:usage
localcoda backend initialization version $APP_VERSION
Usage:
  backend_run [options]

Options:
  -h             displays this help page
  -o <key>=<val> override the configuration option (in the $APPDIR/cfg/conf file). See
                 the content of the $APPDIR/cfg/conf file for specific options to override
:usage
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
   -o) eval "$2"; shift 2 ;;
   -h | --help) usage ;;
   *) error 1 "Unrecognized argument $1. See help!"
    ;;
  esac
done

#Initializa the tutorial volume
check_env TUTORIALS_VOLUME
if [[ -n "$TUTORIALS_VOLUME_ACCESS_MOUNT" ]]; then
  #If local mount, then there is only a copy we need to do
  cp -rf $TAPPDIR/* $TUTORIALS_VOLUME_ACCESS_MOUNT/
elif [[ -n "$TUTORIALS_VOLUME_ACCESS_IMAGE" ]]; then
  #Remote mount, we need to get remote access to it
  if [[ $ORCHESTRATION_ENGINE == "local" ]]; then
    check_sw docker
    
    #Check if volume exists
		docker volume inspect $TUTORIALS_VOLUME
		if [[ $? -ne 0 ]]; then
      echo "Docker volume does not exists. Creating it..."
			docker volume create $TUTORIALS_VOLUME
			[[ $? -ne 0 ]] && error 12 "Failed to create docker volume. Exiting!"
		fi

    #Copy contents into volume
		docker run --rm -v $TAPPDIR:/src:ro -v $TUTORIALS_VOLUME:/dst:rw $TUTORIALS_VOLUME_ACCESS_IMAGE /bin/sh -c 'cp -r -f /src/* /dst/'
		[[ $? -ne 0 ]] && error 12 "Failed to copy data into docker volume. Exiting!"

  elif [[ $ORCHESTRATION_ENGINE == "kubernetes" ]]; then
    check_sw kubectl
		check_env KUBERNETES_NAMESPACE KUBERNETES_BACKEND_WWW_CONFIGMAP
    #Check if the PVC exists, otherwise create it
    kubectl -n "$KUBERNETES_NAMESPACE" get pvc/$TUTORIALS_VOLUME
    if [[ $? -ne 0 ]]; then
      #Creating PVC
      echo "No PVC found. Creating it..."
      cat <<EOF | kubectl -n "$KUBERNETES_NAMESPACE" apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $TUTORIALS_VOLUME
spec:
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  resources:
    requests:
      storage: 1Gi
EOF
      [[ ${PIPESTATUS[1]} -ne 0 ]] && error 3 "Failed to create PVC!"
    fi
    #Run an helper PVC for data copy
		echo "Starting copy helper pod..."
		cat <<EOF | kubectl -n "$KUBERNETES_NAMESPACE" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: localcoda-copy-helper
spec:
  containers:
  - name: helper
    image: $TUTORIALS_VOLUME_ACCESS_IMAGE
    command: ["/bin/sh", "-c", "sleep 3600"]
    volumeMounts:
    - mountPath: /dst
      name: tutorials-path
  volumes:
  - name: tutorials-path
    persistentVolumeClaim:
      claimName: $TUTORIALS_VOLUME
EOF
    [[ $? -ne 0 ]] && error 3 "Failed to create helper pod!"
    kubectl -n "$KUBERNETES_NAMESPACE" wait --for=condition=Ready pod/localcoda-copy-helper --timeout=60s
		[[ $? -ne 0 ]] && error 3 "Helper pod did not start. Maybe something is wrong with your PVC!"
    #Copy the files
		echo "Copying tutorials files..."
		kubectl -n "$KUBERNETES_NAMESPACE" cp $TAPPDIR/* localcoda-copy-helper:/dst/
		res=$?
    #Remove the pod
		echo "Cleaning up..."
		kubectl -n "$KUBERNETES_NAMESPACE" delete pod/localcoda-copy-helper
    #Check result
		[[ $res -ne 0 ]] && error 3 "Failed to copy the files"

    #Check WWW configmap
		echo "Creating/updating WWW configmap..."
		kubectl delete -n "$KUBERNETES_NAMESPACE" configmap/$KUBERNETES_BACKEND_WWW_CONFIGMAP 
    kubectl create -n "$KUBERNETES_NAMESPACE" configmap $KUBERNETES_BACKEND_WWW_CONFIGMAP --from-file="$WWWDIR"
		[[ $res -ne 0 ]] && error 3 "Failed to create configmap"
  else
    error 2 "Orchestration engine $ORCHESTRATION_ENGINE is invalid!"
  fi
else
  error 11 "At least one of TUTORIALS_VOLUME_ACCESS_MOUNT or TUTORIALS_VOLUME_ACCESS_IMAGE variables need to be set"
fi

#all done correctly if we are at this point
echo "Backend initialized correctly!"
exit 0
