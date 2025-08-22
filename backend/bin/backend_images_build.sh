#!/bin/bash

#Basic functions
function error(){
  echo "ERROR: $2"
  exit $1
}

#Get app directory and load basic configuration
which readlink &>/dev/null
[[ $? -ne 0 ]] && error 2 "readlink command not found in the PATH. This is required."

SWDIR="${BASH_SOURCE[0]}"
[[ "${SWDIR:0:1}" == "/" ]] || SWDIR="$PWD/$SWDIR"
cd "${SWDIR%/*}"; SWDIR="$PWD"
APPDIR="${SWDIR%/*}"

#Parse command line parameters
APP_VERSION=0.0.2
function usage {
  cat <<:usage
localcoda backend build images utility version $APP_VERSION
Usage:
  backend_images_build [options]

Options:
  -h             displays this help page
  -E <engine>    virtualization engines to build images for. Can be docker or sysbox.
                 Defaults to $VIRT_ENGINE.
  -Bs <scheme>   base scheme to use for the built images. Defaults to $IMAGES_DOCKER_BASE_SCHEME
                 You can use the following variables in this scheme: \$VIRT_ENGINE as the virtual
  							 engine in use and \$i as the name of the image directory in the "images" folder
  -Bt <tag>      image tag for the built. Defaults to $IMAGE_TAG
  -d <dir>       directory where to find the images to build, in sub-directories. Defaults to
                 "$APPDIR/images/\$VIRT_ENGINE"
  --publish      publish the images after build (do docker push). Do not forget to do a docker
                 login command before running this script
:usage
  exit 1
}

IMAGES_BASE_SCHEME="spinto/localcoda-\$VIRT_ENGINE-\${i,,}"
IMAGES_TAG=latest
VIRT_ENGINE=docker
PUBLISH_IMAGES=false
while [[ "$#" -gt 0 ]]; do
  case "$1" in
   -E) VIRT_ENGINE="$2"; shift 2 ;;
   -Bs) IMAGES_BASE_SCHEME="$2"; shift 2 ;;
	 -Bt) IMAGES_TAG="$2"; shift 2 ;;
	 -d) IMAGES_DIR="$2"; shift 2 ;;
   --publish) PUBLISH_IMAGES=true; shift 1;;
   -h | --help) usage ;;
   *) error 1 "Unrecognized argument $1. See help!"
    ;;
  esac
done

#Engine-specific setup
if [[ "$VIRT_ENGINE" == "docker" ]]; then
  DOCKER_CMD_EXTRA=
	REQUIRED_SW=docker
elif [[ "$VIRT_ENGINE" == "sysbox" ]]; then
  DOCKER_CMD_EXTRA="--runtime=sysbox-runc"
	REQUIRED_SW=docker
else
	error 2 "Unsupported virtualization engine runtime $VIRT_ENGINE"
fi
[[ -z "$IMAGES_DIR" ]] && IMAGES_DIR="$APPDIR/images/$VIRT_ENGINE"
[[ -d "$IMAGES_DIR" ]] || error 4 "Cannot find image dir at $IMAGES_DIR. Make sure you correctly installed the application"

#Check required build software is there
for sw in $REQUIRED_SW; do
  which $sw &>/dev/null
  [[ $? -ne 0 ]] && error 2 "$sw not found in the PATH. This is required."
done

#Start image build
echo "Image build for $VIRT_ENGINE virtualization engine"

#Run pre-configuration scripts
echo "Executing pre scripts..."
cd "$IMAGES_DIR"
for i in *; do
  if [[ ! -L "$i" && -f "$i" ]]; then
    LI=${i%.pre.sh}; [[ "$LI" == "$i" ]] && continue
    LI="${LI##*/}"
    cd "$LI"
    echo "  -> $i..."
    bash ../$i
    cd "$IMAGES_DIR"
  fi
done

#Build basic images
echo "Compiling base images..."
cd "$IMAGES_DIR"
for i in *; do
  if [[ ! -L "$i" && -d "$i" ]]; then
    cd "$i"
		eval IMAGES_BASE="$IMAGES_BASE_SCHEME"
    echo "Building image for $IMAGES_BASE:$IMAGES_TAG"
    tar -czh . | docker build -t $IMAGES_BASE:$IMAGES_TAG -
		[[ ${PIPESTATUS[1]} -ne 0 ]] && error 10 "Failed to build docker image for $i"
    cd "$IMAGES_DIR"
  fi
done

#Execute preload (if any). This is needed for things who need systemd running to be installed/configured, like pulling docker images
echo "Executing preload scripts..."
cd "$IMAGES_DIR"
for LI in *; do
  if [[ ! -L "$LI" && -f "$LI" ]]; then
    i=${LI%.preload.sh}; [[ "$i" == "$LI" ]] && continue
    i="${i##*/}"
		eval IMAGES_BASE="$IMAGES_BASE_SCHEME"
    IMAGE_TORUN="$IMAGES_BASE:$IMAGES_TAG"
    docker run $DOCKER_CMD_EXTRA -d --name build_preloader -v "$SWDIR/images/$LI:/tmp/image_preload.sh:ro" "$IMAGE_TORUN"
		[[ $? -ne 0 ]] && error 12 "Failed to run image preloader container for $i"
    docker exec build_preloader /tmp/image_preload.sh
		[[ $? -ne 0 ]] && error 12 "Failed to run image preloader script for $i"
    echo "waiting for container to shutdown..."
    while [[ `docker ps -a -f "name=build_preloader" --format=json | jq -r .State` != "exited" ]]; do sleep 1; done
    echo "committing image..."
    docker commit build_preloader "$IMAGE_TORUN"
		[[ $? -ne 0 ]] && error 12 "Failed to run image preloader commit for $i"
    docker rm build_preloader
  fi
done

echo "Linking image aliases..."
cd "$IMAGES_DIR"
for i in *; do
  if [[ -L "$i" && -d "$i" ]]; then
		eval IMAGES_BASE="$IMAGES_BASE_SCHEME"
    IMAGE_DEST=$IMAGES_BASE:$IMAGES_TAG
    LI="`readlink -f $i`"
    LI="${LI##*/}"
    ibk="$i"
    i="$LI"
    eval IMAGES_BASE="$IMAGES_BASE_SCHEME"
    IMAGE_SRC=$IMAGES_BASE:$IMAGES_TAG
    i="$ibk"
    echo "  $IMAGE_SRC -> $IMAGE_DEST"
    docker tag $IMAGE_SRC $IMAGE_DEST
		[[ $? -ne 0 ]] && error 12 "Failed to link image alias for $i"
  fi
done

if $PUBLISH_IMAGES; then
  echo "Publishing images..."
  cd "$IMAGES_DIR"
  for i in *; do
    if [[ -d "$i" ]]; then
      eval IMAGES_BASE="$IMAGES_BASE_SCHEME"
      docker push $IMAGES_BASE:$IMAGES_TAG
      [[ $? -ne 0 ]] && error 12 "Failed to push image for $i"
    fi
  done
fi

echo "All done! You can how use your custom images"
