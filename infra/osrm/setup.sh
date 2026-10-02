#!/usr/bin/env bash
# Downloads an OpenStreetMap extract and builds the OSRM routing dataset
# (MLD: extract -> partition -> customize) inside the official Docker image.
#
# Region defaults to New Delhi (BBBike, ~35 MB) - swap it with env vars:
#   OSRM_REGION_URL=... OSRM_REGION_NAME=... ./setup.sh
#
# Runs inside WSL:  wsl -- bash /mnt/c/<repo>/infra/osrm/setup.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
DATA="$DIR/data"
IMAGE="${OSRM_IMAGE:-osrm/osrm-backend:latest}"
REGION_NAME="${OSRM_REGION_NAME:-NewDelhi}"
REGION_URL="${OSRM_REGION_URL:-https://download.bbbike.org/osm/bbbike/NewDelhi/NewDelhi.osm.pbf}"

mkdir -p "$DATA"

# The distro may still carry Docker Desktop's dead context - force the local engine.
docker context use default >/dev/null 2>&1 || true
if ! docker info >/dev/null 2>&1; then
  echo "Docker engine is not running. Repair it first:"
  echo "  wsl -u root -- bash <repo>/_scratch/wsl_docker_setup.sh"
  exit 1
fi

PBF="$DATA/$REGION_NAME.osm.pbf"
if [ ! -s "$PBF" ]; then
  echo "==> downloading $REGION_URL"
  curl -fL --retry 3 --progress-bar -o "$PBF.part" "$REGION_URL"
  mv "$PBF.part" "$PBF"
fi
echo "==> pbf: $(du -h "$PBF" | cut -f1)"

if [ -f "$DATA/$REGION_NAME.osrm.mldgr" ] && [ -f "$DATA/$REGION_NAME.osrm.cell_metrics" ]; then
  echo "==> dataset already built ($REGION_NAME.osrm) - nothing to do"
  exit 0
fi

echo "==> pulling $IMAGE"
docker pull -q "$IMAGE" >/dev/null

echo "==> osrm-extract (car profile)"
docker run --rm -v "$DATA":/data "$IMAGE" osrm-extract -p /opt/car.lua "/data/$REGION_NAME.osm.pbf"

echo "==> osrm-partition (MLD)"
docker run --rm -v "$DATA":/data "$IMAGE" osrm-partition "/data/$REGION_NAME.osrm"

echo "==> osrm-customize (MLD)"
docker run --rm -v "$DATA":/data "$IMAGE" osrm-customize "/data/$REGION_NAME.osrm"

echo "==> dataset ready:"
ls -1 "$DATA/$REGION_NAME.osrm"* | sed 's|.*/|   |'
echo "NEXT: ./start.sh"
