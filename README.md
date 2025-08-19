# Localcoda Interactive Environment

Run interactive learning tutorials on your own server (or your own Kubernetes cluster).

<img width="970" height="515" alt="localcodaimage" src="https://github.com/user-attachments/assets/e67cdac2-5e05-40bc-b442-2494e0316356" />

## Disclaimer

This project is heavily inspired by [Killercoda](https://killercoda.com/) and in no way wants to be a replacement of the [Killercoda](https://killercoda.com/) platform. [Killercoda](https://killercoda.com/) is amazing, and you should use it (and buy their Plus membership). Anyway, there are some limitations in Killercoda, one is that, even with the plus membership, you have at maximum 4GB of RAM and limited CPU power, which may be an issue for some applications, and that the tutorial that you publish are public (even if set not searchable), and you may have some proprietary application you may not want to share in the tutorial, but bind (with its license) in an underlying private image. This project addresses such niche use cases.

## Usage

### Single-scenario run, on a local machine

In this mode you can run a single scenario from a tutorial locally on your machine. You will need, as minimum, [Docker](https://www.docker.com/) to be installed on the machine 

#### Quickstart

To run a single tutorial instance you need first to download your tutorial locally. If you want to run one of the ["examples" scenarios](https://github.com/killercoda/scenarios-docker) from killercoda you can download them from the gitlab via

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

Then run the scenario via

```
backend/bin/backend_run.sh ../scenario-examples upload-assets/index.json
```

If all goes well, you will have now your scenario stated at an url like

```
http://app.localcoda.com/
```

You need now to connect to this address. Anyway, you may not have this address setup in your DNS, so you need to allow your browser to resolve it to the IP of your machine. If you do not have your own DNS service, you can then use Chrome (or any other Chrominum based browser) and start it with the `--host-resolver-rules="MAP *.localcoda.com <ip-of-your-machine>"` option

#### Run using sysbox

The quickstart above will use the default docker virtualization engine to run your tutorial. Docker capabilities are limited, in particular it does not allow to have containers with systemd and requires admin privileges to be given to the container to run docker-in-docker. Thus, not all the tutorials can run on the docker virtualization engine, but only the one that do not make a big use of systemd.

If your tutorial does not work or you want to be more sure your tutorial environment cannot be escaped easily, you can run the backend with the [sysbox](https://github.com/nestybox/sysbox) virtualization engine.

To use sysbox, you need first to meet the [sysbox requirements](https://github.com/nestybox/sysbox/blob/master/docs/distro-compat.md), which are met for the latest Ubuntu 24.04 LTS distribution, and then you need to install it following the [sysbox official installation guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md)

Once you have sysbox installed, test it properly works via

```
docker run --runtime=sysbox-runc --rm -it busybox /bin/echo successful run
```

Then you can run a scenario via sysbox by selecting the sysbox engine with

```
backend/bin/backend_run.sh -o VIRT_ENGINE=sysbox ../scenarios-docker environment-variables/index.json
```

#### More advanced parameters

A full help of the single-scenario run script can be obtained by running

```
backend/bin/backend_run.sh --help
```

An advanced list of configuration options is included in the file

```
backend/cfg/conf
```



#### Image memory limits

Localcoda can enforce memory limits for the executions of scenarios. By default, these are disabled (as having very high limits was the all point of developing this software in the first place), but you can enforce them for each base image by editing the `cfg/imagemap.*` configuration file for your specific virtualization engine.

#### Use custom images

This software comes with two basic images, one implmenting a single node kubernetes cluster (stable version) and one implementing a ubuntu (with docker) machine. You can anyway setup new images.

To do so, you can have a look at the images folder in this repository. A new image can be created as a new directory. The entrypoint (and service, if you are using systemd) need to be configured in your image. You can have a look at the existing images configuration and extend their dockerfiles.

The images can be built via the `backend/bin/backend_images_build.sh` script. 

### Single-scenario run, on a remote kubernetes cluster

This mode allows you to run a single tutorial on a kubernetes cluster for which you have rights

NOTE: TO BE IMPLEMENTED

### Multi-scenario mode, on the local machine

This mode allows oyu to run multiple scenarios on a local VM. Note that this mode is mostly for development, as it will not scale properly. To run a multi-scenario mode service you should use a kubernetes cluster backend

#### Enable multi-tenant

docker run -p 0.0.0.0:8080:8080 -d --name keycloak --restart unless-stopped -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin quay.io/keycloak/keycloak:26.3.2 start-dev

docker run -p 0.0.0.0:8080:8080 -d --name keycloak --restart unless-stopped -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin quay.io/keycloak/keycloak:26.3.2 start-dev --hostname-strict=false

Login to : http://keycloak.localcoda.com:8080/admin
Create a realm
Create some users (or integrate with your IdP of choice like github)


### Multi-scenario mode, on a remote kubernetes cluster

This mode allows multiple users to list multiple tutorial and scenarios and start them

NOTE: TO BE IMPLEMENTED
