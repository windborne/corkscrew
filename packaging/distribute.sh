#!/bin/bash
set -euo pipefail

# Sends all the packages out to S3, brew, apt, etc
# Composes other scripts:
#  1. create_github_release.sh --check
#  2. build_deb.sh
#  3. upload_artifacts.sh
#  4. update_brew.sh
#  5. push_brew.sh
#  6. create_github_release.sh

# Resolve repo root and packaging dir so this can be run from anywhere
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packaging_dir="$repo_root/packaging"

echo "Starting distribution from: $repo_root"

step() {
  local title="$1"; shift
  echo
  echo "==> $title"
  "$@"
  echo "✓ $title"
}

# Check release credentials, artifacts, version commit, and tag safety before
# performing any distribution writes.
step "Check GitHub release prerequisites" \
  bash "$packaging_dir/create_github_release.sh" --check

# 1) Build Debian packages and APT metadata
step "Build Debian packages" bash "$packaging_dir/build_deb.sh"

# 2) Upload artifacts (tarballs, debs, apt metadata, gpg public key) to S3
step "Upload artifacts to S3" bash "$packaging_dir/upload_artifacts.sh"

# 3) Update Homebrew formula based on local macOS tarballs and version
step "Update Homebrew formula" bash "$packaging_dir/update_brew.sh"

# 4) Push Homebrew formula to the tap repository
step "Push Homebrew formula" bash "$packaging_dir/push_brew.sh"

# 5) Create and push the version tag, create the GitHub release, and upload the
# four versioned Linux/macOS tarballs.
step "Publish GitHub release" bash "$packaging_dir/create_github_release.sh"

echo
echo "All distribution steps completed."
