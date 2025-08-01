#!/bin/bash
#Update k3s release and k3s images stored locally
#

[[ -e k3s-airgap-images-amd64-filtered.tar.zst ]] && exit

#Get latest github release
LASTRELEASE="`curl -I -s https://github.com/k3s-io/k3s/releases/latest | sed -n 's|^location: \(.*\)/tag/\([[:print:]]*\).*$|\1/download/\2|p'`"

#Download images
curl -L "$LASTRELEASE/k3s-airgap-images-amd64.tar.zst"  > k3s-airgap-images-amd64.tar.zst

#Filter images
#  remove prevous images (if any)
docker rmi `docker images | grep 'rancher/' | sed 's|^\([^ \t]*\)[ \t]*\([^ \t]*\).*|\1:\2|'`
#  load current images
zstd -d -c k3s-airgap-images-amd64.tar.zst | docker load
#  save only needed images
docker save rancher/mirrored-coredns-coredns rancher/local-path-provisioner rancher/mirrored-pause  | zstd -o k3s-airgap-images-amd64-filtered.tar.zst  
#  clean images again
docker rmi `docker images | grep 'rancher/' | sed 's|^\([^ \t]*\)[ \t]*\([^ \t]*\).*|\1:\2|'`
#  remove old image file
rm k3s-airgap-images-amd64.tar.zst
