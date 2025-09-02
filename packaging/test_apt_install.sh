#!/usr/bin/env bash
set -euo pipefail

# Smoke-test APT install of corkscrew inside Ubuntu 22.04 using the S3-hosted repo
# Requires Docker installed locally.

echo "Starting Ubuntu 22.04 container to test apt install..."

docker run --rm --pull=missing ubuntu:22.04 bash -lc "set -euo pipefail; \
  export DEBIAN_FRONTEND=noninteractive; \
  apt-get update >/dev/null; \
  apt-get install -y --no-install-recommends curl gnupg ca-certificates >/dev/null; \
  install -d -m 0755 /etc/apt/keyrings; \
  curl -fsSL 'https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/apt/public.asc' | gpg --dearmor -o /etc/apt/keyrings/corkscrew.gpg; \
  echo 'deb [signed-by=/etc/apt/keyrings/corkscrew.gpg] https://wb-data-public.s3.us-west-2.amazonaws.com/corkscrew/apt/debs ./' > /etc/apt/sources.list.d/corkscrew.list; \
  apt-get update; \
  apt-get install -y corkscrew-deploys; \
  echo; \
  corkscrew --version"


