#!/usr/bin/env sh

# This script sets up dockerized Redash on Debian 12.x, Ubuntu LTS 20.04 & 22.04, and RHEL (and compatible) 8.x & 9.x
set -eu

REDASH_BASE_PATH=/opt/redash

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

  if [ ! -e "$REDASH_BASE_PATH"/postgres-data ]; then
    mkdir "$REDASH_BASE_PATH"/postgres-data
  fi
}

create_env() {
  echo "** Creating Redash environment file **"

  if [ -e "$REDASH_BASE_PATH"/env ]; then
    rm "$REDASH_BASE_PATH"/env
    touch "$REDASH_BASE_PATH"/env
  fi

  COOKIE_SECRET=$(pwgen -1s 32)
  SECRET_KEY=$(pwgen -1s 32)
  POSTGRES_PASSWORD=$(pwgen -1s 32)
  REDASH_DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres/postgres"

  cat <<EOF >"$REDASH_BASE_PATH"/env
PYTHONUNBUFFERED=0
REDASH_LOG_LEVEL=INFO
REDASH_REDIS_URL=redis://redis:6379/0
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REDASH_COOKIE_SECRET=$COOKIE_SECRET
REDASH_SECRET_KEY=$SECRET_KEY
REDASH_DATABASE_URL=$REDASH_DATABASE_URL
EOF
}

setup_compose() {
  echo "** Creating Redash Docker compose file **"

  cd "$REDASH_BASE_PATH"
  GIT_BRANCH="${REDASH_BRANCH:-master}" # Default branch/version to master if not specified in REDASH_BRANCH env var
  curl -fsSOL https://raw.githubusercontent.com/getredash/setup/"$GIT_BRANCH"/data/compose.yaml
  curl -fsSOL https://raw.githubusercontent.com/getredash/setup/"$GIT_BRANCH"/redash_make_default.sh
  sed -i "s|__BASE_PATH__|${REDASH_BASE_PATH}|" redash_make_default.sh
  sed -i "s|__TARGET_FILE__|$1|" redash_make_default.sh
  chmod +x redash_make_default.sh
  export COMPOSE_PROJECT_NAME=redash
  export COMPOSE_FILE="$REDASH_BASE_PATH"/compose.yaml

  echo "** Initialising fresh Redash database **"
  docker compose run --rm server create_db

  echo
  echo "*********************"
  echo "** Starting Redash **"
  echo "*********************"
  docker compose up -d
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
setup_compose "$PROFILE"

echo
echo "Redash has been installed and is ready for configuring at http://$(hostname -f):5000"
echo

echo "If you want Redash to be your default Docker Compose project when you login to this server"
echo "in future, then please run $REDASH_BASE_PATH/redash_make_default.sh"
echo
echo "That will set some Docker specific environment variables just for Redash.  If you"
echo "already use Docker Compose on this computer for other things, you should probably skip it."