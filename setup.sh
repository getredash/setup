#!/usr/bin/env bash
# This script setups dockerized Redash on Ubuntu 18.04.
set -eu

REDASH_BASE_PATH="/Users/sild/Projects/Personal/local_db/db_data"

create_directories() {
    if [[ ! -e $REDASH_BASE_PATH ]]; then
        mkdir -p $REDASH_BASE_PATH
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
    REQUESTED_CHANNEL=stable
    #LATEST_VERSION=`curl -s "https://version.redash.io/api/releases?channel=$REQUESTED_CHANNEL"  | json_pp  | grep "docker_image" | head -n 1 | awk 'BEGIN{FS=":"}{print $3}' | awk 'BEGIN{FS="\""}{print $1}'`

    cp data/docker-compose.yml ${REDASH_BASE_PATH}/docker-compose.yml
    cd $REDASH_BASE_PATH
    GIT_BRANCH="${REDASH_BRANCH:-master}" # Default branch/version to master if not specified in REDASH_BRANCH env var
    export COMPOSE_PROJECT_NAME=local_db
    export COMPOSE_FILE=${REDASH_BASE_PATH}/docker-compose.yml
    docker-compose run --rm server create_db
    docker-compose up -d
}

create_directories
create_config
setup_compose
