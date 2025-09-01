FROM ubuntu:24.04

#Support for systemctl and modprobe in the container
COPY journalctl systemctl /usr/bin/

#Add basic required packages
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y && apt-get install -y kmod iproute2 iptables curl wget man vim sudo jq git gawk sed python3 bzip2 xz-utils 7zip zip unzip psmisc bash-completion && apt-get clean all && rm -rf /var/lib/apt/lists/*

#Nicer shell loggin
RUN echo "PS1='\\\\[\\\\e]0;\\\\h: \\\\w\\\\a\\\\]\\\\h:\\\\w$ '" >> /root/.bashrc

#Add support for docker and k3s (if you need to install it later)
#Volumes needed for Docker (cannot use overlay otherwise)
VOLUME /var/lib/docker
#Volumes needed for K3S (cannot use overlay otherwise)
VOLUME /var/lib/kubelet
VOLUME /var/lib/rancher/k3s
VOLUME /var/lib/cni
VOLUME /var/log

# Install K3s and and Helm.
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_ENABLE=true INSTALL_K3S_SKIP_START=true INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb --disable=metrics-server" sh - && echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml\nalias k=kubectl\nsource /etc/bash_completion\nsource <(kubectl completion bash)' >> ~/.bashrc && systemctl enable k3s

# Preload images (as in airgapped environment)
#RUN mkdir -p /var/lib/rancher/k3s/agent/images/ && curl -L -o /var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar.zst "https://github.com/k3s-io/k3s/releases/download/`k3s --version | sed -n 's|^k3s version \([^ ]*\).*$|\1|p'`/k3s-airgap-images-amd64.tar.zst"
COPY k3s-airgap-images-amd64-filtered.tar.zst /var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar.zst

#Local-coda specific application installation (blocking entrypoint version)
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y && apt-get install -y nginx bash jq && apt-get clean all && rm -rf /var/lib/apt/lists/* && systemctl disable nginx && curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 > /usr/bin/ttyd && chmod +x /usr/bin/ttyd && ln -s /etc/localcoda/entrypoint-poweroff /usr/sbin/poweroff
COPY localcoda-app /etc/localcoda
ENTRYPOINT ["/bin/bash","/etc/localcoda/entrypoint-blocking"]
