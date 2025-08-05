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
SWDIR="`readlink -f "$0"`"; SWDIR="${SWDIR%/*}"
APPDIR="`readlink -f "${SWDIR%/*}"`"; APPDIR="${APPDIR%/}"
WWWDIR=`readlink -f $APPDIR/www`
[[ -e "$APPDIR/cfg/conf" ]] || error 1 "Cannot find configuration file at $APPDIR/cfg/conf"
source $APPDIR/cfg/conf

#Load commandline options
APP_VERSION=0.0.1
function usage {
  cat <<:usage
localcoda backend stop version $APP_VERSION
Usage:
  backend_stop [options] <uuid>

Where the arguments are:
  <uuid>         Stop the tutorial for the given uuid. Mandatory

Options:
  -h             displays this help page
  -o <key>=<val> override the configuration option (in the $APPDIR/cfg/conf file). See
                 the content of the $APPDIR/cfg/conf file for specific options to override
:usage
  exit 1
}

[[ -z "$1" ]] && usage
LOCAL_UUID=
while [[ "$#" -gt 0 ]]; do
  case "$1" in
   -o) eval "$2"; shift 2 ;;
   -h | --help) usage ;;
   *) if [[ -z "$LOCAL_UUID" ]]; then
	      LOCAL_UUID="$1"
      else
        error 1 "Unrecognized argument $1. See help!"
      fi
      shift 1
    ;;
  esac
done
[[ -z "$LOCAL_UUID" ]] && error "Please specify a UUID to delete"
#Check required configuration is set
check_env ORCHESTRATION_ENGINE EXECUTION_NAME_SCHEME
if [[ $ORCHESTRATION_ENGINE == "local" ]]; then
  check_sw docker
	check_env LOCAL_IPPORT
elif [[ $ORCHESTRATION_ENGINE == "kubernetes" ]]; then
  check_sw kubectl
	check_env KUBERNETES_NAMESPACE
else
	error 2 "Orchestration engine $ORCHESTRATION_ENGINE is invalid!"
fi

#Set defaults
eval EXECUTION_NAME=$EXECUTION_NAME_SCHEME

#Use the orchestration engine to run the backend instance
if [[ $ORCHESTRATION_ENGINE == "local" ]]; then
  docker stop $EXECUTION_NAME

elif [[ $ORCHESTRATION_ENGINE == "kubernetes" ]]; then
  
	kubectl -n "$KUBERNETES_NAMESPACE" delete pod/$EXECUTION_NAME service/$EXECUTION_NAME ingress/$EXECUTION_NAME-app ingress/$EXECUTION_NAME-proxy

fi
#all done correctly if we are at this point
exit 0
