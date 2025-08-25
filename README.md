# Localcoda Interactive Environment

Run interactive learning tutorials on your own server (or your own Kubernetes cluster).

<img width="970" height="515" alt="localcodaimage" src="https://github.com/user-attachments/assets/e67cdac2-5e05-40bc-b442-2494e0316356" />

## Disclaimer

This project is heavily inspired by [Killercoda](https://killercoda.com/) and in no way wants to be a replacement of the [Killercoda](https://killercoda.com/) platform. [Killercoda](https://killercoda.com/) is amazing, and you should use it (and buy their Plus membership). Anyway, there are some limitations in Killercoda, one is that, even with the plus membership, you have at maximum 4GB of RAM and limited CPU power, which may be an issue for some applications, and that the tutorial that you publish are public (even if set not searchable), and you may have some proprietary application you may not want to share in the tutorial, but bind (with its license) in an underlying private image. This project addresses such niche use cases.

## Quickstart

### Single-scenario run, on a local machine

In this mode you can run a single scenario from a tutorial locally on your machine. You will need, as minimum, [Docker](https://www.docker.com/) to be installed on the machine.

First you need to download your scenarios locally. If you want to run one of the ["examples" scenarios](https://github.com/killercoda/scenarios-docker) from killercoda you can download them from the gitlab via

```
git clone https://github.com/killercoda/scenario-examples
```

Then you need to download this application

```
git clone https://github.com/spinto/localcoda
cd localcoda
```

Ensure you have docker installed and you can run it in your use

```
docker ps
```

Then run the scenario via (note the use of the absolute path for the downloaded tutorial folder, which is required for local scenario run)

```
backend/bin/backend_run.sh $PWD/../scenario-examples upload-assets/index.json
```

If all goes well, you will have now your scenario stated at an url like

```
http://cc1934ba-ac00-4388-9208-eda7af057679-app.0a1d0903.nip.io:33406
```

You need now to connect to this address (and ignore the "site is not secure" alerts, if any).

Once you have completed your scenario, you can stop it by executing the `poweroff` command in the scenario web shell or by using the `backend/bin/backend_stop.sh` command (with the id of your scenario).

### Full mode, on a Kubernetes cluster

In the full mode, you will deploy a multi-tutorial and multi-user option on a Kubernetes cluster.

In order to deploy localcoda on a on a Kubernetes cluster you need
- A [Kubernetes](https://kubernetes.io/) client (kubectl) is installed and configured on your cluster. To check this works, you can run `kubectl get pods`. If it gives you no error, you should be fine.
- Your Kubernetes cluster supports [ReadWriteMany](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes) Access Mode for your PVCs. This is not entirely common, you may have to install an [NFS provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) or a custom CSI controller (like [Longhorn](https://longhorn.io/)) to enable this.

If you have the above, then first download the localcoda latest release via

```
git clone https://github.com/spinto/localcoda
```

Edit the `backend/cfg/conf` file and set:
- `ORCHESTRATION_ENGINE=kubernetes`
- `EXT_DOMAIN_NAME` to a DNS address mapping the Kubernetes Ingress external load balancer IP. If you do not have a DNS server on your disposal, you can use a [nip.io](https://sslip.io/) address or your custom address (which will need to be mapped into your /etc/hosts file)

Create the localcoda default namespace via

```
kubectl create namespace localcoda
```

Create an admin/admin user account (which we will use for initial setup)

```
echo 'admin:$2y$05$V5LcntAIsPpcra54gIebGe/6gER/FW8dwzU2em0iG/C3Q/5oRW0Ye' > tutorials/data/users.htpasswd
```

Initialize the localcoda tutorial volume. This will be used to store users configuration, scenarios, etc..

```
backend/bin/backend_volume.sh init
```

Run the frontend with local httpasswd authentication enabled via

```
frontend/bin/frontend_run.sh --auth $PWD/frontend/cfg/oauth2-proxy.htpasswd.cfg
```

Once executed successfully, you can connect at the listed address and login via with the admin/admin account.

You can then execute the tutorials in the "Admin" area to get information on how to manage users, add scenarios, configure permissions, etc...

## Configuration

The main application configuration is contained in the `backend/cfg/conf` file. Options are described in the file, and allow you to fine-tune scenario execution parameters such as the possibility to auto-terminate scenarios after a given time, limit parallel scenarios runs or configure deployment options.

For more information about specific configuration options, like adding your own custom backend scenario image or using the sysbox virtualization engine for additional security and isolation, you can refer to the [ADVANCED_CONFIG.md](docs/ADVANCED_CONFIG.md) guide. Have a look at it if you want to setup a production environment.

## More deployment options

The quickstart mode on top displays only some of the most common deployments and basic customizations. There are other modes you can deploy, like the full mode on a local server instead of a Kubernetes cluster, or a multi-tutorial mode without authorization. For a detailed deployment guide on a single virtual machine, you can look at the [DEPLOY_LOCAL.md](docs/DEPLOY_LOCAL.md) file. For a detailed deployment guive on a Kubernetes cluster, you can look at the [DEPLOY_KUBERNETES.md](docs/DEPLOY_KUBERNETES.md) file.
