FROM ubuntu:24.04

#Support for systemctl and modprobe in the container
COPY journalctl systemctl /usr/bin

#Basic required packages
RUN apt update && apt-get upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get install -y kmod iproute2 iptables curl wget man vim sudo jq git gawk sed python3 bzip2 xz-utils 7zip zip unzip psmisc && apt clean all && rm -rf /var/lib/apt/lists/*

#Nicer shell loggin
RUN echo "PS1='\\\\[\\\\e]0;\\\\h: \\\\w\\\\a\\\\]\\\\h:\\\\w$ '" >> /root/.bashrc

#Install docker engine
RUN apt update && DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose && apt clean all && rm -rf /var/lib/apt/lists/*

#Add support for docker and k3s (if you need to install it later)
#Volumes needed for Docker (cannot use overlay otherwise)
VOLUME /var/lib/docker
#Volumes needed for K3S (cannot use overlay otherwise)
VOLUME /var/lib/kubelet
VOLUME /var/lib/rancher/k3s
VOLUME /var/lib/cni
VOLUME /var/log

#Local-coda specific application installation
RUN apt update && apt-get upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get install -y nginx bash jq && apt clean all && rm -rf /var/lib/apt/lists/* && systemctl disable nginx && curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.i686 > /usr/bin/ttyd && chmod +x /usr/bin/ttyd
COPY entrypoint.sh prepare_image.sh entrypoint-blocking /etc/localcoda/
COPY poweroff /usr/sbin/poweroff

ENTRYPOINT ["/bin/bash","/etc/localcoda/entrypoint-blocking"]
