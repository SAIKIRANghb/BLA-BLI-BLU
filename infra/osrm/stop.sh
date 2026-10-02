#!/usr/bin/env bash
# Stops the OSRM route container (dataset stays on disk).
set -euo pipefail
docker context use default >/dev/null 2>&1 || true
docker rm -f "${OSRM_CONTAINER:-osrm}" >/dev/null 2>&1 && echo "osrm stopped" || echo "osrm was not running"
