#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
mkdir -p dist

export QE_PACKAGE_UID="$(id -u)"
export QE_PACKAGE_GID="$(id -g)"
docker_security="$(docker info --format '{{json .SecurityOptions}}')"
if [[ $docker_security == *name=rootless* ]]; then
    # Rootless Docker maps container root to the host user.
    export QE_PACKAGE_UID=0 QE_PACKAGE_GID=0
fi
exec docker compose -f compose.yaml run --build --rm -T package
