# Setup script for Redash with Docker on Linux

This is a reference setup for Redash on a single Linux server.

It uses Docker and Docker Compose for deployment and management.

This is the same setup we use for our official images (for AWS & Google Cloud) and can be used as reference if you want
to manually setup Redash in a different environment (different OS or different deployment location).

- `setup.sh` is the script that installs everything and creates the directories.
- `compose.yaml` is the Docker Compose setup we use.
- `packer.json` is Packer configuration we use to create the Cloud images.

## Tested

- Alma Linux 8.x & 9.x
- CentOS Stream 9.x
- Debian 12.x
- Fedora 38, 39 & 40
- Oracle Linux 9.x
- Red Hat Enterprise Linux 8.x & 9.x
- Rocky Linux 8.x & 9.x
- Ubuntu LTS 20.04 & 22.04

## How to use this

This script should be run as the `root` user on a supported Linux system (as per above list):

```
# ./setup.sh
```

When run, the script will install the needed packages (mostly Docker) then install Redash, ready for you to configure
and begin using.

> [!TIP]
> If you are not on a supported Linux system, you can manually install 'docker' and 'docker compose',  
> then run the script to start the Redash installation process.

> [!IMPORTANT]
> The very first time you load your Redash web interface it can take a while to appear, as the background Python code
> is being compiled.  On subsequent visits, the pages should load much quicker (near instantly).

## Optional parameters

The setup script has the following optional parameters: `--dont-start`, `--preview`, `--version`, and `--overwrite`.

These can be used independently of each other, or in combinations (with the exception that `--preview` and `--version` cannot be used together).

### --preview

When the `--preview` parameter is given, the setup script will install the latest `preview` 
[image from Docker Hub](https://hub.docker.com/r/redash/redash/tags) instead of using the latest preview release.

```
# ./setup.sh --preview
```

### --version

When the `--version` parameter is given, the setup script will install the specified version of Redash instead of the latest stable release.

```
# ./setup.sh --version 25.1.0
```

This option allows you to install a specific version of Redash, which can be useful for testing, compatibility checks, or ensuring reproducible environments.

> [!NOTE]
> The `--version` and `--preview` options cannot be used together.

### Default Behavior

When neither `--preview` nor `--version` is specified, the script will automatically detect and install the latest stable release of Redash using the GitHub API.

### --overwrite

> [!CAUTION]
> ***DO NOT*** use this parameter if you want to keep your existing Redash installation!  It ***WILL*** be overwritten.

When the `--overwrite` option is given, the setup script will delete the existing Redash environment file
(`/opt/redash/env`) and Redash database, then set up a brand new (empty) Redash installation.

```
# ./setup.sh --overwrite
```

### --dont-start

When this option is given, the setup script will install Redash without starting it afterwards.

This is useful for people wanting to customise or modify their Redash installation before it starts for the first time.

```
# ./setup.sh --dont-start
```

## FAQ

### Can I use this in production?

For small scale deployments -- yes. But for larger deployments we recommend at least splitting the database (and
probably Redis) into its own server (preferably a managed service like RDS) and setting up at least 2 servers for
Redash for redundancy. You will also need to tweak the number of workers based on your usage patterns.

### How do I upgrade to newer versions of Redash?

See [Upgrade Guide](https://redash.io/help/open-source/admin-guide/how-to-upgrade).

### How do I use `setup.sh` on a different operating system?

You will need to create a docker installation function that suits your operating system, and maybe other functions as
well.

The `install_docker_*()` functions in setup.sh shouldn't be too hard to adapt to other Linux distributions.

### How do I remove Redash if I no longer need it?

1. Stop the Redash containers and remove the images using `docker compose -f /opt/redash/compose.yaml down --volumes --rmi all`.
2. Remove the following lines from `~/.profile` and `~/.bashrc` if they're present.

   ```
   export COMPOSE_PROJECT_NAME=redash
   export COMPOSE_FILE=/opt/redash/compose.yaml
   ```

3. Delete the Redash folder using `sudo rm -fr /opt/redash`
