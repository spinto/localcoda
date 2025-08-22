#!/bin/bash
#execute as a post commit as we need the initd running to start this

#Just wait for the K3S cluster to startup automatically, this way you will pull the required images
echo "waiting for k3s to start..."
while ! kubectl wait --for=condition=Ready --all=true -A pod --timeout=1m &>/dev/null; do sleep 1; done
