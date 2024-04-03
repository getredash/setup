#!/usr/bin/env sh

# This script sets up dockerized Redash on Debian 12.x, Ubuntu LTS 20.04 & 22.04, and RHEL (and compatible) 8.x & 9.x
set -eu

REDASH_BASE_PATH=/opt/redash
OVERWRITE=no
PREVIEW=no
PORT=5000

# Ensure the script is being run as root
ID=$(id -u)
if [ "0$ID" -ne 0 ]
  then echo "Please run this script as root"
  exit
fi

# Ensure the script is running on something it can work with
if [ ! -f /etc/os-release ]; then
  echo "Unknown Linux distribution.  This script presently works only on Debian, Ubuntu, and RHEL (and compatible)"
  exit
fi

# Parse any user provided parameters
opts="$(getopt -o oph -l overwrite,preview,help --name "$0" -- "$@")"
eval set -- "$opts"

while true
do
  case "$1" in
    -o|--overwrite)
      OVERWRITE=yes
      shift
      ;;
    -p|--preview)
      PREVIEW=yes
      PORT=5001
      shift
      ;;
    -h|--help)
      echo "Redash setup script usage: $0 [-p|--preview] [-o|--overwrite]"
      echo "  The --preview option uses the Redash 'preview' Docker image instead of the last stable release"
      echo "  The --overwrite option replaces any existing configuration with a fresh new install"
      exit 1
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

install_docker_debian() {
  echo "** Installing Docker (Debian) **"

  export DEBIAN_FRONTEND=noninteractive
  apt-get -qqy update
  DEBIAN_FRONTEND=noninteractive apt-get -qqy -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
  apt-get -yy install apt-transport-https ca-certificates curl software-properties-common pwgen gnupg

  # Add Docker GPG signing key
  if [ ! -f "/etc/apt/keyrings/docker.gpg" ]; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  # Add Docker download repository to apt
  cat <<EOF >/etc/apt/sources.list.d/docker.list
deb [arch=""$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable
EOF
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_rhel() {
  echo "** Installing Docker (RHEL and compatible) **"

  # Add EPEL package repository
  if [ "x$DISTRO" = "xrhel" ]; then
    # Genuine RHEL doesn't have the epel-release package in its repos
    RHEL_VER=$(. /etc/os-release && echo "$VERSION_ID" | cut -d "." -f1)
    if [ "0$RHEL_VER" -eq "9" ]; then
      yum install -qy https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    else
      yum install -qy https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    fi
    yum install -qy yum-utils
  else
    # RHEL compatible distros do have epel-release available
    yum install -qy epel-release yum-utils
  fi
  yum update -qy

  # Add Docker package repository
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  yum update -qy

  # Install Docker
  yum install -qy docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin pwgen

  # Start Docker and enable it for automatic start at boot
  systemctl start docker && systemctl enable docker
}

install_docker_ubuntu() {
  echo "** Installing Docker (Ubuntu) **"

  export DEBIAN_FRONTEND=noninteractive
  apt-get -qqy update
  DEBIAN_FRONTEND=noninteractive sudo -E apt-get -qqy -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
  apt-get -yy install apt-transport-https ca-certificates curl software-properties-common pwgen gnupg

  # Add Docker GPG signing key
  if [ ! -f "/etc/apt/keyrings/docker.gpg" ]; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  # Add Docker download repository to apt
  cat <<EOF >/etc/apt/sources.list.d/docker.list
deb [arch=""$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable
EOF
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

create_directories() {
  echo "** Creating $REDASH_BASE_PATH directory structure for Redash **"

  if [ ! -e "$REDASH_BASE_PATH" ]; then
    mkdir -p "$REDASH_BASE_PATH"
    chown "$USER:" "$REDASH_BASE_PATH"
  fi

  if [ -e "$REDASH_BASE_PATH"/postgres-data ]; then
    # PostgreSQL database directory seems to exist already

    if [ "x$OVERWRITE" = "xyes" ]; then
      # We've been asked to overwrite the existing database, so delete the old one
      echo "Shutting down any running Redash instance"
      if [ -e "$REDASH_BASE_PATH"/compose.yaml ]; then
        docker compose -f "$REDASH_BASE_PATH"/compose.yaml down
      fi

      echo "Removing old Redash PG database directory"
      rm -rf "$REDASH_BASE_PATH"/postgres-data
      mkdir "$REDASH_BASE_PATH"/postgres-data
    fi
  else
    mkdir "$REDASH_BASE_PATH"/postgres-data
  fi
}

create_env() {
  echo "** Creating Redash environment file **"

  # Minimum mandatory values (when not just developing)
  COOKIE_SECRET=$(pwgen -1s 32)
  SECRET_KEY=$(pwgen -1s 32)
  PG_PASSWORD=$(pwgen -1s 32)
  DATABASE_URL="postgresql://postgres:${PG_PASSWORD}@postgres/postgres"

  if [ -e "$REDASH_BASE_PATH"/env ]; then
    # There's already an environment file

    if [ "x$OVERWRITE" = "xno" ]; then
      echo
      echo "Environment file already exists, reusing that one + and adding any missing (mandatory) values"

      # Add any missing mandatory values
      REDASH_COOKIE_SECRET=
      REDASH_COOKIE_SECRET=$(. "$REDASH_BASE_PATH"/env && echo "$REDASH_COOKIE_SECRET")
      if [ -z "$REDASH_COOKIE_SECRET" ]; then
        echo "REDASH_COOKIE_SECRET=$COOKIE_SECRET" >> "$REDASH_BASE_PATH"/env
        echo "REDASH_COOKIE_SECRET added to env file"
      fi

      REDASH_SECRET_KEY=
      REDASH_SECRET_KEY=$(. "$REDASH_BASE_PATH"/env && echo "$REDASH_SECRET_KEY")
      if [ -z "$REDASH_SECRET_KEY" ]; then
        echo "REDASH_SECRET_KEY=$SECRET_KEY" >> "$REDASH_BASE_PATH"/env
        echo "REDASH_SECRET_KEY added to env file"
      fi

      POSTGRES_PASSWORD=
      POSTGRES_PASSWORD=$(. "$REDASH_BASE_PATH"/env && echo "$POSTGRES_PASSWORD")
      if [ -z "$POSTGRES_PASSWORD" ]; then
        POSTGRES_PASSWORD=$PG_PASSWORD
        echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> "$REDASH_BASE_PATH"/env
        echo "POSTGRES_PASSWORD added to env file"
      fi

      REDASH_DATABASE_URL=
      REDASH_DATABASE_URL=$(. "$REDASH_BASE_PATH"/env && echo "$REDASH_DATABASE_URL")
      if [ -z "$REDASH_DATABASE_URL" ]; then
        echo "REDASH_DATABASE_URL=postgresql://postgres:${POSTGRES_PASSWORD}@postgres/postgres" >> "$REDASH_BASE_PATH"/env
        echo "REDASH_DATABASE_URL added to env file"
      fi

      echo
      return
    fi

    # Move any existing environment file out of the way
    mv -f "$REDASH_BASE_PATH"/env "$REDASH_BASE_PATH"/env.old
  fi

  echo "Generating brand new environment file"

  cat <<EOF >"$REDASH_BASE_PATH"/env
PYTHONUNBUFFERED=0
REDASH_LOG_LEVEL=INFO
REDASH_REDIS_URL=redis://redis:6379/0
REDASH_COOKIE_SECRET=$COOKIE_SECRET
REDASH_SECRET_KEY=$SECRET_KEY
POSTGRES_PASSWORD=$PG_PASSWORD
REDASH_DATABASE_URL=$DATABASE_URL
REDASH_ENFORCE_CSRF=true
REDASH_GUNICORN_TIMEOUT=60
EOF
}

setup_compose() {
  echo "** Creating Redash Docker compose file **"

  cd "$REDASH_BASE_PATH"
  GIT_BRANCH="${REDASH_BRANCH:-master}" # Default branch/version to master if not specified in REDASH_BRANCH env var
  if [ "x$OVERWRITE" = "xyes" ]; then
    mv -f compose.yaml compose.yaml.old
  fi
  curl -fsSOL https://raw.githubusercontent.com/getredash/setup/"$GIT_BRANCH"/data/compose.yaml
  TAG="10.1.0.b50633"
  if [ "x$PREVIEW" = "xyes" ]; then
    TAG="preview"
  fi
  sed -i "s|__TAG__|$TAG|" compose.yaml
  # The preview image uses a different port to access the web interface
  sed -i "s|__PORT__|$PORT|" compose.yaml
  export COMPOSE_FILE="$REDASH_BASE_PATH"/compose.yaml
  export COMPOSE_PROJECT_NAME=redash

  echo "** Initialising Redash database **"
  docker compose run --rm server create_db

  echo
  echo "*********************"
  echo "** Starting Redash **"
  echo "*********************"
  docker compose up -d
}

setup_make_default() {
  echo "** Creating redash_make_default.sh script **"

  curl -fsSOL https://raw.githubusercontent.com/getredash/setup/"$GIT_BRANCH"/redash_make_default.sh
  sed -i "s|__COMPOSE_FILE__|$COMPOSE_FILE|" redash_make_default.sh
  sed -i "s|__TARGET_FILE__|$PROFILE|" redash_make_default.sh
  chmod +x redash_make_default.sh
}

echo
echo "Redash installation script. :)"
echo

# Run the distro specific Docker installation
DISTRO=$(. /etc/os-release && echo "$ID")
PROFILE=.profile
case "$DISTRO" in
debian)
  install_docker_debian
  ;;
ubuntu)
  install_docker_ubuntu
  ;;
almalinux|centos|ol|rhel|rocky)
  PROFILE=.bashrc
  install_docker_rhel
  ;;
*)
  echo "This doesn't seem to be a Debian, Ubuntu, nor RHEL (compatible) system, so this script doesn't know how to add Docker to it."
  echo
  echo "Please contact the Redash project via GitHub and ask about getting support added, or add it yourself and let us know. :)"
  echo
  exit
  ;;
esac

# Do the things that aren't distro specific
create_directories
create_env
setup_compose
setup_make_default

echo
echo "Redash has been installed and is ready for configuring at http://$(hostname -f):$PORT"
echo

echo "If you want Redash to be your default Docker Compose project when you login to this server"
echo "in future, then please run $REDASH_BASE_PATH/redash_make_default.sh"
echo
echo "That will set some Docker specific environment variables just for Redash.  If you"
echo "already use Docker Compose on this computer for other things, you should probably skip it."