# Localcoda deployment on a kubernetes cluster

To deploy localcoda directly on a kubernetes cluster you can use the `kubernetes` orchestrator.

## Pre-requisites

The following pre-requistes needs to be met to deploy localcoda on a Kubernetes cluster:
- A [Kubernetes](https://kubernetes.io/) client (kubectl) is installed and configured on your cluster. To check this works, you can run `kubectl get pods`. If it gives you no error, you should be fine.
- You have downloaded the localcoda latest release. To do so, you can run `git clone https://github.com/spinto/localcoda`
- You have setup in your `backend\cfg\conf` file `ORCHESTRATION_ENGINE=kubernetes`
- Your Kubernetes cluster supports [ReadWriteMany](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes) Access Mode for your PVCs. This is not entirely common, you may have to install an [NFS provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) or a custom CSI controller (like [Longhorn](https://longhorn.io/)) to enable this.
- You have a wildcard DNS address mapping the Kubernetes Ingress external load balancer IP to the `EXT_DOMAIN_NAME` defined in your `backend\cfg\conf`. In more details, `*$EXT_DOMAIN_NAME` need to resolve to your external load balancer IP instance. By default, `EXT_DOMAIN_NAME` is set to `.\$NIP_ADDRESS` (not the . on front), which will use [nip.io](https://sslip.io/) to generate a wildcard DNS entry mapping to your server internal IP. This will fail in a Kubernetes cluster, so or you replace the `EXT_DOMAIN_NAME` with the values of your custom domain (mind the . in front, e.g. setting it to `.localcoda.com` will generate addresses like `*.localcoda.com`) or your use a value taken from [nip.io](https://sslip.io/) mapping your actual external load balancer IP instance.
- You need to create a namespace for localcoda to run in the cluster. Its name is set into the `KUBERNETES_NAMESPACE` variable in the `backend\cfg\conf` file to `localcoda` (you an edit this value to your liking). If you do not have a `localcoda` namespace in your cluster, you can create one by running `kubectl create namespace localcoda`

## Single-scenario run

To run a single scenario on your kubernetes cluster, you will need to download it into the `tutorials/data` directory, for example via

```
( cd tutorials/data/; git clone https://github.com/killercoda/scenario-examples; )
```

Then initialize the backend tutorials volume (so you can copy there this scenario)

```
backend/bin/backend_volume.sh init
```

Once this is completed, you can run the scenario via

```
backend/bin/backend_run.sh -o TUTORIALS_VOLUME_ACCESS_MOUNT=$PWD/tutorials/data scenario-examples upload-assets/index.json
```

### Listing and stopping scenarios

If you want to list the running scenarios you can use the command

```
backend/bin/backend_ls.sh | jq
```

If you want to stop them, you need first the scenario ID, which you can get from the command above, then run

```
backend/bin/backend_stop.sh <instance-id>
```

### More fine-tuning

To change the domain name or for other deployment parameters relevant for your production environment, have a look at the [Advanced localcoda configuration guide](ADVANCED_CONFIG.md)

Additional deployment options are also available from the `backend/bin/backend_run.sh -h` help.

## Multi-scenario run

### Quick-run

In a multi-scenario run you will deploy on Kubernetes the localcoda frontend. Instructions to do so are in the [Quickstart of the README.md guide](../README.md#full-mode-on-a-kubernetes-cluster)

## Stopping frontend

To stop the frontend you can run

```
frontend/bin/frontend_stop.sh
```

If you want to stop the running backends, refer to the commands above (for the single-scenario run)

### More fine-tuning (and authentication for frontend)

To update authentication, change the domain name or for other deployment parameters relevant for your production environment, have a look at the [Advanced localcoda configuration guide](ADVANCED_CONFIG.md)

Additional deployment options are also available from the `frontend/bin/frontend_run.sh -h` help.

