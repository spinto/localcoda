#Start from systemd and docker image of ubuntu 24
FROM nestybox/ubuntu-noble-systemd-docker:latest

#Change user to root
USER "root"

#Add basic required packages
RUN apt update && apt-get upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get install -y kmod iproute2 iptables curl wget man vim sudo jq git gawk sed python3 bzip2 xz-utils 7zip zip unzip psmisc && apt clean all && rm -rf /var/lib/apt/lists/*

#Nicer shell loggin
RUN echo "PS1='\\\\[\\\\e]0;\\\\h: \\\\w\\\\a\\\\]\\\\h:\\\\w$ '" >> /root/.bashrc

#Local-coda specific application installation
RUN apt update && apt-get upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get install -y nginx bash jq && apt clean all && rm -rf /var/lib/apt/lists/* && systemctl disable nginx && curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.i686 > /usr/bin/ttyd && chmod +x /usr/bin/ttyd
COPY entrypoint.sh /etc/localcoda/entrypoint.sh
COPY localcoda.service /etc/systemd/system/localcoda.service
RUN systemctl enable localcoda 
