#!/bin/bash

#Basic functions
function error(){
  echo "ERROR: $2"
  exit $1
}

#Get app directory and load basic configuration
which readlink &>/dev/null
[[ $? -ne 0 ]] && error 2 "readlink command not found in the PATH. This is required."

SWDIR="`readlink -f "$0"`"; SWDIR="${SWDIR%/*}"
APPDIR="`readlink -f "${SWDIR%/*}"`"; APPDIR="${APPDIR%/}"

#Parse command line parameters
APP_VERSION=0.0.2
function usage {
  cat <<:usage
localcoda frontend build image utility version $APP_VERSION
Usage:
  frontend_image_build [options]

Options:
  -h             displays this help page
  -Bs <scheme>   base scheme to use for the built images. Defaults to $IMAGES_DOCKER_BASE_SCHEME
                 You can use the following variables in this scheme: \$VIRT_ENGINE as the virtual
  							 engine in use and \$i as the name of the image directory in the "images" folder
  -Bt <tag>      image tag for the built. Defaults to $IMAGE_TAG

  --publish      publish the images after build (do docker push). Do not forget to do a docker
                 login command before running this script
:usage
  exit 1
}

IMAGES_BASE_SCHEME="spinto/localcoda-frontend"
IMAGES_TAG=latest
PUBLISH_IMAGES=false
while [[ "$#" -gt 0 ]]; do
  case "$1" in
   -Bs) IMAGES_BASE_SCHEME="$2"; shift 2 ;;
	 -Bt) IMAGES_TAG="$2"; shift 2 ;;
   --publish) PUBLISH_IMAGES=true; shift 1;;
   -h | --help) usage ;;
   *) error 1 "Unrecognized argument $1. See help!"
    ;;
  esac
done

#Engine-specific setup
DOCKER_CMD_EXTRA=
REQUIRED_SW=docker
IMAGES_DIR="$APPDIR/app"

#Check required build software is there
for sw in docker; do
  which $sw &>/dev/null
  [[ $? -ne 0 ]] && error 2 "$sw not found in the PATH. This is required."
done

#Start image build
eval IMAGES_BASE="$IMAGES_BASE_SCHEME"

#Build basic images
echo "Compiling base images..."
cd "$IMAGES_DIR"
tar -czh . | docker build -t $IMAGES_BASE:$IMAGES_TAG -
    [[ ${PIPESTATUS[1]} -ne 0 ]] && error 10 "Failed to build docker image for $i"

if $PUBLISH_IMAGES; then
  echo "Publishing images..."
  docker push $IMAGES_BASE:$IMAGES_TAG
fi

echo "All done! You can how use your custom images"
