#!/usr/bin/env bash
set -euo pipefail

# The released emulator signs Blob/Queue requests using a Date header alongside
# x-ms-date. Azurite 3.38 rejects that signature; 3.37 is the compatible backend.
# Pin the multi-architecture manifest so an upstream latest update cannot change CI.
AZURITE_IMAGE='mcr.microsoft.com/azure-storage/azurite:3.37.0@sha256:830430c1da1a2d537e08f3e6764dd1f5ae00cf0346bcaf625b968ec3f0971fd5'
docker pull "$AZURITE_IMAGE"
# The emulator currently requests this unversioned name and uses the local cache.
docker tag "$AZURITE_IMAGE" mcr.microsoft.com/azure-storage/azurite:latest
