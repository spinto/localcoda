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
localcoda frontend stop version $APP_VERSION
Usage:
  frontend_stop [options]

Options:
  -h             displays this help page
  -n <name>      Container/deployment name. Default is '$FRONTEND_NAME'
  -o <key>=<val> override the configuration option (in the $APPDIR/cfg/conf file). See
                 the content of the $APPDIR/cfg/conf file for specific options to override

:usage
  exit 1
}

FRONTEND_NAME="localcoda-frontend"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
   -n) FRONTEND_NAME="$1"; shift 2 ;;
   -o) eval "$2"; shift 2 ;;
   -h | --help) usage ;;
   *) error 1 "Unrecognized argument $1. See help!"
    ;;
  esac
done

echo "Stopping frontend..."
check_env ORCHESTRATION_ENGINE FRONTEND_NAME
if [[ $ORCHESTRATION_ENGINE == "local" ]]; then
  check_sw docker
  docker stop $FRONTEND_NAME
  exit $?
elif [[ $ORCHESTRATION_ENGINE == "kubernetes" ]]; then
  check_sw kubectl
	check_env KUBERNETES_NAMESPACE
  kubectl delete -n "$KUBERNETES_NAMESPACE" deployment/$FRONTEND_NAME service/$FRONTEND_NAME ingress/$FRONTEND_NAME configmap/$FRONTEND_NAME-cfg
  exit $?
else
	error 2 "Orchestration engine $ORCHESTRATION_ENGINE is invalid!"
fi

