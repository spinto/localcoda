#/bin/bash

#Start k3 service
echo "Starting k3s service..."
systemctl start k3s
#Wait for system pods to start
while ! kubectl wait --for=condition=Ready --all=true -A pod --timeout=1m &>/dev/null; do sleep 1; done
echo "Kubernetes cluster is up!"
