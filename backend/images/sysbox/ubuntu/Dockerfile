#Start from systemd and docker image of ubuntu 24
FROM nestybox/ubuntu-noble-systemd-docker:latest

#Change user to root
USER "root"

#Add basic required packages
RUN apt update && apt-get upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get install -y kmod iproute2 iptables curl wget man vim sudo jq git gawk sed python3 bzip2 xz-utils 7zip zip unzip psmisc bash-completion && apt clean all && rm -rf /var/lib/apt/lists/*

#Nicer shell loggin
RUN echo "PS1='\\\\[\\\\e]0;\\\\h: \\\\w\\\\a\\\\]\\\\h:\\\\w$ '" >> /root/.bashrc

#Local-coda specific application installation (systemd version / non-blocking entrypoint version)
COPY localcoda.service /etc/systemd/system/localcoda.service
#Target architecture (amd64, arm64). Set automatically by BuildKit; defaults to the build host architecture on the legacy builder
ARG TARGETARCH
RUN apt update && apt-get upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get install -y nginx libnginx-mod-http-perl bash jq && apt clean all && rm -rf /var/lib/apt/lists/* && systemctl disable nginx && TTYD_ARCH=$(case "${TARGETARCH:-$(dpkg --print-architecture)}" in arm64) echo aarch64;; *) echo x86_64;; esac) && curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.$TTYD_ARCH > /usr/bin/ttyd && chmod +x /usr/bin/ttyd && systemctl enable localcoda
COPY localcoda-app /etc/localcoda
