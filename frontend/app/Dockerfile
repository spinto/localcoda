#This is the main application container
FROM ubuntu:24.04

#Basic required packages
RUN apt update && apt-get upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get install -y curl bash jq grep docker.io nginx fcgiwrap apache2-utils && apt clean all && rm -rf /var/lib/apt/lists/* && curl -L "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" > /usr/bin/kubectl && chmod +x /usr/bin/kubectl && OAUTH2_PROXY_VERSION=v7.12.0 && curl -L https://github.com/oauth2-proxy/oauth2-proxy/releases/download/$OAUTH2_PROXY_VERSION/oauth2-proxy-$OAUTH2_PROXY_VERSION.linux-amd64.tar.gz | tar -xzO oauth2-proxy-$OAUTH2_PROXY_VERSION.linux-amd64/oauth2-proxy > /usr/bin/oauth2-proxy && chmod +x /usr/bin/oauth2-proxy

#Run as non-root user
USER www-data

#Install the application
COPY --chown=www-data:www-data . /opt/localcoda

WORKDIR /opt/localcoda/

ENTRYPOINT ["/opt/localcoda/entrypoint.sh"]
