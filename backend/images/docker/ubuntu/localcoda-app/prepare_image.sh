#/bin/bash

#Start k3 service
echo "Starting docker service..."
nohup dockerd &>/var/log/dockerd.log </dev/null &

#Wait for docker to start
while ! docker ps &>/dev/null; do sleep 1; done
echo "Docker is up!"
