# Advanced localcoda configuration (for production environements)

This guide will describe the advanced localcoda configuration you should consider setting up to run a production environment. Most of the configuration can be applied via the `backend/cfg/conf` file.

## Configure user authentication (for multi-scenario deployments only)

User authentication in the localcoda frontend is by default managed using [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/), which can allow you to connect to any OIDC Identity Provider (like Google, Github or your own organization provider, see the [providers list](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/)).

Configuration is performed using a oauth2-proxy TOML configuration files, like the [oauth2-proxy.cfg.example](https://github.com/oauth2-proxy/oauth2-proxy/blob/master/contrib/oauth2-proxy.cfg.example) file, with only provider configuration.

An example configurarion which enables only local authentication via a passwd file is stored in [the frontend cfg directory](../frontend/cfg/oauth2-proxy.htpasswd.cfg), you can edit it and add your specific [provider confguration paramters](https://oauth2-proxy.github.io/oauth2-proxy/configuration/providers/)

To start the frontend with the sample passwd authentication enabled, you can run

```
frontend/bin/frontend_run.sh --auth $PWD/frontend/cfg/oauth2-proxy.htpasswd.cfg
```

If you try to access the frontend, you will be now faced with a "Forbidden" page inviting you to login. Before doing so, we need to have an user and to have it configured for access.

If you have not configured your own OIDC Identity Provider, but you are using the sample passwd authentication configuration, you can just create a random admin/admin user by running

```
echo 'admin:$2y$05$V5LcntAIsPpcra54gIebGe/6gER/FW8dwzU2em0iG/C3Q/5oRW0Ye' > tutorials/data/users.htpasswd
```

If instead you have configured your own OIDC Identity Provider, you need first to identify your admin user account username. To do so, login using your account then find your username in the top-right button. Note your username and edit the `tutorials/data/users.json` file changing the name of the admin user from "admin" to your username.

After you have done your changes, re-init the volume via

```
backend/bin/backend_volume.sh init
```

And you should be now able to access the localcoda instance with your admin account. You can then now follow the "Manage users" tutorial into the "Admin" area to provide access to other users.

NOTE that, the htpasswd is only for development and example. You should use your own OIDC external Identity Provider. For example, if you want to add more users to the htpasswd or if you want to change the admin user password, you need to use the `htpasswd -B users.htpasswd <username>` command inside the users tutorial and then perform a `frontend/bin/frontend_restart.sh` command to reload the new htpasswd file.

## Deploy on your own domain

Localcoda needs a wildcard DNS domain to be assigned to its frontend/backend instances in order to make them accessible. By default, this is generated from (nip.io)[https://sslip.io/], as set into the `EXT_DOMAIN_NAME` variable in the `backend/cfg/conf` file.

For a production environment, you should probably assign to localcoda your own DNS sub-domain and make it easily resolvable for your users. Once you have setup that, you need to update the `EXT_DOMAIN_NAME` variable in the `backend/cfg/conf` file. Note that the localcoda application DNS entries are generated as `<appname>$EXT_DOMAIN_NAME` so you need to have a separator in the `EXT_DOMAIN_NAME`. For example, you can use `.localcoda.com` and the app will be accessible from `*.localcoda.com`. You may also use a dash and have for example `-lc.mydomain.com` and the app will be accessible from `*.mydomain.com` but all its DNS entries will finish with `-lc` (this is useful when you want to share `*.mydomain.com` with other services and you do not want to set a specific sub-domain).

In addition, you can also fine-tune the way localcoda generates domain names in your sub-domain for its backend and frontend runs, by setting up the `EXT_FT_MAINHOST_SCHEME`, `EXT_BK_MAINHOST_SCHEME` and `EXT_BK_PROXYHOST_SCHEME` variables in the `backend/cfg/conf` file. Anyway, unless you really do not like the default configuration, I would suggest to keep it like it is, to avoid issues in the communication between backend and frontend.

## Secure with HTTPS

In a production environment, and to avoid nasty "Your site is not secure" errors, you should secure the localcoda endpoint with HTTPS.

Localcoda does not directly support this, so you need to put a reverse proxy in front of it with HTTPS support, and assign to it a wildcard SSL certificate mapping your localcoda wildcard DNS domain.

You can do that by changing the default configuration of your Kubernetes cluster ingress, or setting up a custom local reverse proxy. I will not give you a guide on how to do this, just google it or ask your favourite AI assistant.

Once you have configured your reverse proxy or ingress, you need to change the `EXT_PROTO` variable in the `backend/cfg/conf` file, set it to `https` and re-deploy your localcoda instance. This way localcoda will know it needs to redirect you to HTTPS.

## Isolate internal pod network

In a production environment, on Kubernetes, you way want to isolate the pods running in the localcoda namespace, so that users running a tutorial cannot use it to connect to you internal Kubernetes network services or to other tutorials or use the internal Kubernetes DNS to find the IDs of other users tutorials.

Once you isolate the localcoda backend pods, they will be able only to connect to the internet, which will mean they will be also kicked out from the internal Kubernetes DNS. For this reason, before isolating the localcoda backend pod network, you should edit the `backend/cfg/conf` file and set the `KUBERNETES_BK_DNS` variable to DNS servers outside of the Kubernetes cluster (e.g. your organization DNSes or public IP DNSes). NOTE: You need then to apply the new configuration by running again the `frontend/bin/frontend_run.sh`.

Now, to isolate your pod network, you can apply the sample kubernetes configuration in `frontend/cfg/isolate-namespace-pods.yaml`. Before doing so, ensure the CIDR in the `frontend/cfg/isolate-namespace-pods.yaml` (`except` rule) matches the CIDR of your internal kubernetes network, then deploy it via

```
kubectl apply -n localcoda -f frontend/cfg/isolate-namespace-pods.yaml
```

## Run using sysbox

The default docker virtualization engine configured in the `backend/cfg/conf` is Docker. Docker capabilities are limited, in particular it does not allow to have containers with systemd and requires admin privileges to be given to the container to run docker-in-docker. Thus, not all the tutorials can run on the docker virtualization engine, but only the one that do not make a big use of systemd.

If your tutorial does not work or you want to be more sure your tutorial environment cannot be escaped easily, you can run the backend with the [sysbox](https://github.com/nestybox/sysbox) virtualization engine configured in the `backend/cfg/conf` file.

To use sysbox, you need first to meet the [sysbox requirements](https://github.com/nestybox/sysbox/blob/master/docs/distro-compat.md), which are met for the latest Ubuntu 24.04 LTS distribution, and then you need to install it following the [sysbox official installation guide](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md)

Once you have sysbox installed, test it properly works via

```
docker run --runtime=sysbox-runc --rm -it busybox /bin/echo successful run
```

Then you can run a scenario via sysbox by selecting the sysbox engine with

```
backend/bin/backend_run.sh -o VIRT_ENGINE=sysbox ../scenarios-docker environment-variables/index.json
```

## Set scenario memory and CPU limits

Localcoda can enforce memory limits for the executions of scenarios. By default, these are disabled (as not having to worry about limited scenario memory/cpu was the all point of developing this software in the first place), but if you are running a production environment you should still enforce them for each base image by editing the `cfg/imagemap.*` configuration file for your specific virtualization engine.

## Use custom images for your scenario

This software comes with two basic images backends which can be used by your scenarios, one implmenting a single node kubernetes cluster (stable version) and one implementing a single-node ubuntu (with docker) machine. You can anyway setup new images for your specific scenarios.

To do so, you can have a look at the images folder in this repository. A new image can be created as a new directory. The entrypoint (and service, if you are using systemd) need to be configured in your image. You can have a look at the existing images configuration and extend their dockerfiles.

The images can be built (and published) via the `backend/bin/backend_images_build.sh` script.

After the build of the images, you can edit the `cfg/imagemap.*` configuration file (the one for your specific virtualization engine) and add a reference to the image which will be used in your custom scenario `index.json` file (in the `backend.imageid` field)

