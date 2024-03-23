#!/usr/bin/env sh

# Trivial script to add Redash to the user login profile

cat <<EOF >>~/.profile
# Added by Redash 'redash_make_default.sh' script
export COMPOSE_PROJECT_NAME=redash
export COMPOSE_FILE=__BASE_PATH__/compose.yaml
EOF
echo "Redash has now been set as the default Docker Compose project"
