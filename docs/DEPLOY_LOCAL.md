# Localcoda deployment on a single server

To deploy localcoda directly on a single server you can use the `local` orchestrator.

## Pre-requisites

The following pre-requistes needs to be met to deploy localcoda on a single server:
- [Docker](https://www.docker.com/) is installed on your server. Check the [installation guide](https://docs.docker.com/engine/install/) on how to install it.
- Your user has rights to run Docker. To check this works, you can run `docker ps`. If it gives you no error, you should be fine.
- You have downloaded the localcoda latest release. To do so, you can run `git clone https://github.com/spinto/localcoda`
- You have setup in your `backend\cfg\conf` file `ORCHESTRATION_ENGINE=local`
- You have a wildcard DNS address mapping the server local IP to the `EXT_DOMAIN_NAME` defined in your `backend\cfg\conf`. In more details, `*$EXT_DOMAIN_NAME` need to resolve to your server instance. By default, `EXT_DOMAIN_NAME` is set to `.\$NIP_ADDRESS`, which will use [nip.io](https://sslip.io/) to generate a wildcard DNS entry mapping to your server internal IP. You can keep using this if you do not know how to setup use things like a wildcard DNS.

## Single-scenario run

### Quick-run

In a single-scenario run you will run only the backend. Instructions to do so are in the [Quickstart of the README.md guide](../README.md#single-scenario-run-on-a-local-machine)

### Listing and stopping scenarios

If you want to list the running scenarios you can use the command

```
backend/bin/backend_ls.sh
```

If you want to stop them, you need first the scenario ID, which you can get from the command above, then run

```
backend/bin/backend_stop.sh <instance-id>
```

### Setting your own port

By default localcoda will open a random port for the backend, this is generated in the interval between the `LOCAL_RANDOMPORT_MIN` and `LOCAL_RANDOMPORT_MAX` parameters in the `backend\cfg\conf` file. This port needs to be accessible from your firewall (unless you are using a proxy on front, as below).

You can avoid a random port and set manually your own specific port by editing the `LOCAL_INT_IPPORT` paramter in the `backend\cfg\conf` file and setting a specific port instead of the default `\$RANDOM_PORT`.

### Using a proxy on front

If you want to run multiple backends but access them from a single port, the recommended way is to use the multi-scenario mode below.

If you do not want to do that, you can manually setup a reverse proxy on front of your application and set the `LOCAL_INT_F_PROXY` parameter to `true`. This will configure backends to respond to a `-<LOCAL_PORT>\$EXT_DOMAIN_NAME` address. You need then to configure your reverse proxy to map this address. For Nginx, you can do that with the following configuration

```
  server {
    listen $LOCAL_EXT_IPPORT;
    server_name ~-(?<redport>[0-9]+)\\.$EXT_DOMAIN_NAME\$;
    location / {
      proxy_pass http://127.0.0.1:\$redport;
      proxy_set_header Host \$http_host;
      proxy_set_header X-Forwarded-Host \$http_host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header Host \$host;
      proxy_redirect off;
      proxy_buffering off;
      proxy_hide_header access-control-allow-origin;
      add_header Access-Control-Allow-Origin *;
    }
  }
```

Note that this solution will open a security hole into you local machine, as, via the reverse proxy, an user could access any local port.

### More fine-tuning

To change the domain name or for other deployment parameters relevant for your production environment, have a look at the [Advanced localcoda configuration guide](ADVANCED_CONFIG.md)

Additional deployment options are also available from the `backend/bin/backend_run.sh -h` help.

## Multi-scenario run

In a multi-scenario run you can start locally an instance capable to start multiple scenarios and manage multiple users.

The multi-scenario run uses a volume to store the tutorials, the scenarios the users and their configuration. To create this volume you need first to run

```
backend/bin/backend_volume.sh init
``` 

Then you can run the frontend via

```
frontend/bin/frontend_run.sh
```

You will get an IP like

```
http://app.0aa611a4.nip.io/
```

You can now connect to this IP to manage the server.

To understand how to manage the server, follow the tutorials in the "Admin" area.

## Stopping frontend

To stop the frontend you can run

```
frontend/bin/frontend_stop.sh
```

If you want to stop the running backends, refer to the commands above (for the single-scenario run)

## Using a single local port

In its default configuration, once a scenario is started, the frontend will redirect you to its backend which will be on a randomly generated port beween the `LOCAL_RANDOMPORT_MIN` and `LOCAL_RANDOMPORT_MAX` port values defined in the `backend/cfg/conf` configuration file. You will need to allow in your firewall incoming connections to these ports.

If you do not want to do that, you can enable instead the `LOCAL_INT_F_PROXY` parameter in the `backend/cfg/conf` by setting it to `true`. If you do so, and then re-start the frontend, the frontend will proxy the local backends. Note that this solution will open a security hole into you local machine, as, via the reverse proxy, an user could access any local port.

### More fine-tuning (and authentication for frontend)

To enable authentication, change the domain name or for other deployment parameters relevant for your production environment, have a look at the [Advanced localcoda configuration guide](ADVANCED_CONFIG.md)

Additional deployment options are also available from the `frontend/bin/frontend_run.sh -h` help.
