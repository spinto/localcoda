#/bin/bash
#Run for debug and test

#Basic functions
function error(){
  echo "ERROR: $2" >&2
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
WWWDIR="$APPDIR/www"
[[ -e "$APPDIR/cfg/conf" ]] || error 1 "Cannot find configuration file at $APPDIR/cfg/conf"
source $APPDIR/cfg/conf

#Load commandline options
APP_VERSION=0.0.2
function usage {
  cat <<:usage
localcoda backend ls version $APP_VERSION
Usage:
  backend_ls [options] [uuid]

Where the arguments are:
  <uuid>         optional. Query for a custom uuid, instead of checking all the possible
                 uuids

Options:
  -h             displays this help page
  -o <key>=<val> override the configuration option (in the $APPDIR/cfg/conf file). See
                 the content of the $APPDIR/cfg/conf file for specific options to override
  -U <username>  filter running instance by a given <username>. Useful if you are managing
                 multi-tenant executions
:usage
  exit 1
}

LOCAL_UUID=
INSTANCE_USERNAME=
while [[ "$#" -gt 0 ]]; do
  case "$1" in
   -o) eval "$2"; shift 2 ;;
   -U) INSTANCE_USERNAME="$2"; shift 2 ;;
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
#Check required configuration is set
check_env ORCHESTRATION_ENGINE EXECUTION_NAME_SCHEME 

#Calculate dynamic paths
eval INT_BASEPATH=$INT_BASEPATH_SCHEME
eval EXECUTION_NAME=$EXECUTION_NAME_SCHEME

#Use the orchestration engine to run the backend instance
if [[ $ORCHESTRATION_ENGINE == "local" ]]; then
  check_sw docker

  echo "["
  DOCKER_EXTRA_SEL=
  [[ -n "$INSTANCE_USERNAME" ]] && DOCKER_EXTRA_SEL="-f label=user=$INSTANCE_USERNAME"
  s=
  docker ps -f "name=$EXECUTION_NAME" $DOCKER_EXTRA_SEL --format '{{.Names}}' | while read cn; do
    #get info from container
    docker exec $cn /bin/bash -c '[[ -e /etc/localcoda/ready ]]'
    if [[ $? -ne 0 ]]; then
      rs="false"
    else
      rs="true"
    fi
    cat << EOF
  $s{
    "id":"`docker inspect $cn --format '{{ index .Config.Labels "instanceid" }}'`",
    "user":"`docker inspect $cn --format '{{ index .Config.Labels "user" }}'`",
    "ready":"$rs",
    "access_url":"`docker inspect $cn --format '{{ index .Config.Labels "readyurl" }}'`",
    "instance_name":"$cn",
    "tutorial_path":"`docker inspect $cn --format '{{ index .Config.Labels "tutorialpath" }}'`",
    "start_time": "`docker inspect $cn --format '{{ index .Config.Labels "starttime" }}'`",
    "max_time": "`docker inspect $cn --format '{{ index .Config.Labels "maxtime" }}'`"
  }
EOF
    [[ -z "$s" ]] && s=,
  done
  echo "]"

elif [[ $ORCHESTRATION_ENGINE == "kubernetes" ]]; then
  check_sw kubectl
  check_env KUBERNETES_NAMESPACE

  KUBECTL_EXTRA_SEL=
  [[ -n "$INSTANCE_USERNAME" ]] && KUBECTL_EXTRA_SEL=",localcoda-user=$INSTANCE_USERNAME"
  kubectl get pod -n "$KUBERNETES_NAMESPACE" --selector=localcoda-instanceid,job-name$KUBECTL_EXTRA_SEL -o jsonpath='{"["}{range .items[*]}{"{\"id\":\""}{.metadata.labels.localcoda-instanceid}{"\",\"user\":\""}{.metadata.labels.localcoda-user}{"\",\"ready\":\""}{.status.containerStatuses[*].ready}{"\",\"access_url\":\""}{.metadata.annotations.readyurl}{"\",\"instance_name\":\"job/"}{.metadata.labels.job-name}{"\",\"tutorial_path\":\""}{.metadata.annotations.tutorialpath}{"\",\"start_time\":\""}{.metadata.annotations.starttime}{"\",\"max_time\":\""}{.metadata.annotations.maxtime}{"\"},"}{end}{"]"}' | sed 's/,]$/]/'
  [[ $? -ne 0 ]] && error 44 "Failed to run kubernetes get pod"

else
  error 2 "Orchestration engine is invalid!"
fi
#all done correctly if we are at this point
exit 0
