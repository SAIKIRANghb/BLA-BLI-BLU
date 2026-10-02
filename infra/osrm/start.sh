#!/usr/bin/env bash
# Starts the OSRM route service (osrm-routed, MLD) on port 5000 and waits
# until it answers a real route query. The container is named `osrm` with
# --restart unless-stopped, so it comes back after a WSL restart (systemd
# docker service is enabled by the repair script).
#
# Runs inside WSL:  wsl -- bash /mnt/c/<repo>/infra/osrm/start.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
DATA="$DIR/data"
IMAGE="${OSRM_IMAGE:-osrm/osrm-backend:latest}"
NAME="${OSRM_CONTAINER:-osrm}"
REGION_NAME="${OSRM_REGION_NAME:-NewDelhi}"

docker context use default >/dev/null 2>&1 || true

if [ ! -f "$DATA/$REGION_NAME.osrm.mldgr" ] || [ ! -f "$DATA/$REGION_NAME.osrm.cell_metrics" ]; then
  echo "No dataset found - run ./setup.sh first."
  exit 1
fi

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --restart unless-stopped \
  -p 5000:5000 \
  -v "$DATA":/data \
  "$IMAGE" osrm-routed --algorithm mld "/data/$REGION_NAME.osrm" >/dev/null

echo "waiting for $NAME to answer (Delhi sanity route)..."
for _ in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:5000/route/v1/driving/77.2090,28.6139;77.2001,28.5494?overview=false" >/dev/null; then
    echo "OSRM ready: http://127.0.0.1:5000  (container: $NAME)"
    exit 0
  fi
  sleep 1
done

echo "OSRM did not become healthy. Logs:"
docker logs --tail 40 "$NAME"
exit 1
