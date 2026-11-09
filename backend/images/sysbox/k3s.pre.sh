#!/bin/bash
#Update k3s release and k3s images stored locally
#

#Target architecture, using the k3s release asset naming (amd64, arm64). Defaults to the local docker server architecture
ARCH="${ARCH:-`docker version --format '{{.Server.Arch}}'`}"

[[ -e k3s-airgap-images-$ARCH-filtered.tar.zst ]] && exit

#Get latest github release
LASTRELEASE="`curl -I -s https://github.com/k3s-io/k3s/releases/latest | sed -n 's|^location: \(.*\)/tag/\([[:print:]]*\).*$|\1/download/\2|p'`"

#Download images
curl -L "$LASTRELEASE/k3s-airgap-images-$ARCH.tar.zst"  > k3s-airgap-images-$ARCH.tar.zst

#Filter images
#  remove prevous images (if any)
docker rmi `docker images | grep 'rancher/' | sed 's|^\([^ \t]*\)[ \t]*\([^ \t]*\).*|\1:\2|'`
#  load current images
zstd -d -c k3s-airgap-images-$ARCH.tar.zst | docker load
#  save only needed images (an explicit platform selection is needed when generating for a foreign architecture, docker save fails or picks the host variant otherwise)
SAVE_PLATFORM=
[[ "$ARCH" != "`docker version --format '{{.Server.Arch}}'`" ]] && SAVE_PLATFORM="--platform linux/$ARCH"
docker save $SAVE_PLATFORM rancher/mirrored-coredns-coredns rancher/local-path-provisioner rancher/mirrored-pause  | zstd -o k3s-airgap-images-$ARCH-filtered.tar.zst
#  clean images again
docker rmi `docker images | grep 'rancher/' | sed 's|^\([^ \t]*\)[ \t]*\([^ \t]*\).*|\1:\2|'`
#  remove old image file
rm k3s-airgap-images-$ARCH.tar.zst
