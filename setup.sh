#!/usr/bin/env bash
# This script setups dockerized Redash on Amazon Linux 2.
set -eu

REDASH_BASE_PATH=/opt/redash

install_docker(){
    sudo yum -y update
    sudo amazon-linux-extras install epel
    sudo yum install -y pwgen

    # Install Docker
    sudo yum install -y docker
    sudo systemctl enable docker

    # Install Docker Compose
    wget https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)
    sudo mv docker-compose-$(uname -s)-$(uname -m) /usr/local/bin/docker-compose
    sudo chmod -v +x /usr/local/bin/docker-compose
    docker-compose -v
}

create_directories() {
    if [[ ! -e $REDASH_BASE_PATH ]]; then
        sudo mkdir -p $REDASH_BASE_PATH
        sudo chown $USER:$USER $REDASH_BASE_PATH
    fi

    if [[ ! -e $REDASH_BASE_PATH/postgres-data ]]; then
        mkdir $REDASH_BASE_PATH/postgres-data
    fi
}

create_config() {
    if [[ -e $REDASH_BASE_PATH/env ]]; then
        rm $REDASH_BASE_PATH/env
        touch $REDASH_BASE_PATH/env
    fi

    COOKIE_SECRET=$(pwgen -1s 32)
    SECRET_KEY=$(pwgen -1s 32)
    POSTGRES_PASSWORD=$(pwgen -1s 32)
    REDASH_DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres/postgres"

    echo "PYTHONUNBUFFERED=0" >> $REDASH_BASE_PATH/env
    echo "REDASH_LOG_LEVEL=INFO" >> $REDASH_BASE_PATH/env
    echo "REDASH_REDIS_URL=redis://redis:6379/0" >> $REDASH_BASE_PATH/env
    echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> $REDASH_BASE_PATH/env
    echo "REDASH_COOKIE_SECRET=$COOKIE_SECRET" >> $REDASH_BASE_PATH/env
    echo "REDASH_SECRET_KEY=$SECRET_KEY" >> $REDASH_BASE_PATH/env
    echo "REDASH_DATABASE_URL=$REDASH_DATABASE_URL" >> $REDASH_BASE_PATH/env
}

setup_compose() {
#    REDASH_VERSION=10.1.0.b50633

    cd $REDASH_BASE_PATH
    GIT_BRANCH="${REDASH_BRANCH:-master}" # Default branch/version to master if not specified in REDASH_BRANCH env var
    wget https://raw.githubusercontent.com/motoy3d/redash-setup/${GIT_BRANCH}/data/docker-compose.yml
#    sed -ri "s/image: redash\/redash:([A-Za-z0-9.-]*)/image: redash\/redash:$REDASH_VERSION/" docker-compose.yml
    echo "export COMPOSE_PROJECT_NAME=redash" >> ~/.profile
    echo "export COMPOSE_FILE=/opt/redash/docker-compose.yml" >> ~/.profile
    export COMPOSE_PROJECT_NAME=redash
    export COMPOSE_FILE=/opt/redash/docker-compose.yml

    sudo sed -ri "s/HOME\/bin/HOME\/bin:\/usr\/local\/bin/" /root/.bash_profile
    sudo sed -e 's/secure_path.*/secure_path = \/sbin:\/bin:\/usr\/sbin:\/usr\/bin:\/usr\/local\/bin/' /etc/sudoers | sudo EDITOR=tee visudo >/dev/null

    sudo docker-compose run --rm server create_db
    sudo docker-compose up -d
}

install_docker
create_directories
create_config
setup_compose