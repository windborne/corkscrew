#!/usr/bin/env bash
set -euo pipefail
umask 077

# Build a Debian package for corkscrew using Docker and fpm.
# - Reads the version from corkscrew/version.rb (like packaging/update_brew.sh)
# - Uses packaging/corkscrew-<version>-linux-{x86_64,arm64}.tar.gz
# - Outputs .deb files into packaging/dist/

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packaging_dir="$repo_root/packaging"
version_file="$repo_root/corkscrew/version.rb"
dockerfile="$packaging_dir/Dockerfile.deb"

if [[ ! -f "$version_file" ]]; then
  echo "ERROR: Version file not found: $version_file" >&2
  exit 1
fi

version="$(awk -F"'" '/VERSION *=/{print $2}' "$version_file" | tr -d '[:space:]')"
if [[ -z "$version" ]]; then
  echo "ERROR: Could not parse version from $version_file" >&2
  exit 1
fi

image_tag="corkscrew-deb-builder:${version}"
indexer_image_tag="corkscrew-deb-indexer:${version}"

echo "Building deb-builder image: $image_tag"
DOCKER_BUILDKIT=1 docker build -f "$dockerfile" -t "$image_tag" "$packaging_dir" | cat

# Build a cached indexer image with dpkg-dev installed once
if ! docker image inspect "$indexer_image_tag" >/dev/null 2>&1; then
  echo "Building deb-indexer image: $indexer_image_tag"
  DOCKER_BUILDKIT=1 docker build -f "$dockerfile" --build-arg INCLUDE_DPKG_DEV=1 -t "$indexer_image_tag" "$packaging_dir" | cat
fi

mkdir -p "$packaging_dir/debs"
mkdir -p "$packaging_dir/gpg"
chmod 700 "$packaging_dir/gpg" 2>/dev/null || true

ensure_gpg_key() {
  # If no secret key exists, generate a simple unattended key
  if ! gpg --homedir "$packaging_dir/gpg" --list-secret-keys --with-colons | grep -q "^sec"; then
    echo "Generating GPG key for signing in $packaging_dir/gpg"
    cat >"$packaging_dir/gpg/batch" <<EOF
%echo Generating RSA signing key
Key-Type: RSA
Key-Length: 3072
Subkey-Type: RSA
Subkey-Length: 3072
Name-Real: Corkscrew Builder
Name-Email: builder@corkscrew.local
Expire-Date: 0
%no-protection
%commit
%echo done
EOF
    gpg --batch --homedir "$packaging_dir/gpg" --generate-key "$packaging_dir/gpg/batch"
  fi

  # Always (re)export ASCII armored keys for container import
  local fpr
  fpr=$(gpg --homedir "$packaging_dir/gpg" --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')
  if [[ -n "$fpr" ]]; then
    gpg --homedir "$packaging_dir/gpg" --armor --export "$fpr" > "$packaging_dir/gpg/public.asc"
    gpg --homedir "$packaging_dir/gpg" --armor --export-secret-keys "$fpr" > "$packaging_dir/gpg/secret.asc"
    chmod 600 "$packaging_dir/gpg/public.asc" "$packaging_dir/gpg/secret.asc" 2>/dev/null || true
  fi
}

get_signing_fpr() {
  gpg --homedir "$packaging_dir/gpg" --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}'
}

build_one() {
  local arch_slug="$1"   # x86_64 or arm64 (tarball suffix)
  local dpkg_arch
  case "$arch_slug" in
    x86_64) dpkg_arch=amd64 ;;
    arm64)  dpkg_arch=arm64 ;;
    *) echo "Unknown arch: $arch_slug" >&2; exit 1 ;;
  esac

  local tarball="$packaging_dir/corkscrew-${version}-linux-${arch_slug}.tar.gz"
  if [[ ! -f "$tarball" ]]; then
    echo "ERROR: Missing tarball: $tarball" >&2
    exit 1
  fi

  echo
  echo "==> Building .deb for $arch_slug (version $version)"
  local signing_fpr
  signing_fpr=$(get_signing_fpr || true)
  docker run --rm \
    -e VERSION="$version" \
    -e TAR_PATH="/in/$(basename "$tarball")" \
    -e ARCH="$dpkg_arch" \
    -e SIGN_DEBS="1" \
    -e PACKAGE_NAME="corkscrew-deploys" \
    -e BIN_NAME="corkscrew" \
    -e LIB_DIR_NAME="corkscrew" \
    -e GPG_DIR="/gpg" \
    ${signing_fpr:+-e GPG_KEY_ID="$signing_fpr"} \
    -v "$packaging_dir":/in:ro \
    -v "$packaging_dir/gpg":/gpg:ro \
    -v "$packaging_dir/debs":/out \
    "$image_tag"
}

ensure_gpg_key
build_one x86_64
build_one arm64

echo
echo "Artifacts in: $packaging_dir/debs"

echo "Generating Packages and Packages.gz for flat APT repo ..."
# Generate Packages and Packages.gz for flat APT repo
if command -v docker >/dev/null 2>&1; then
  docker run --rm --entrypoint /bin/bash -e LC_ALL=C -v "$packaging_dir/debs":/repo -w /repo "$indexer_image_tag" -lc "dpkg-scanpackages . /dev/null > Packages && gzip -n -c -f -9 Packages > Packages.gz"
elif command -v dpkg-scanpackages >/dev/null 2>&1; then
  LC_ALL=C dpkg-scanpackages "$packaging_dir/debs" /dev/null > "$packaging_dir/debs/Packages"
  gzip -n -c -f -9 "$packaging_dir/debs/Packages" > "$packaging_dir/debs/Packages.gz"
else
  echo "Warning: neither docker nor dpkg-scanpackages available; skipping Packages index generation" >&2
fi

# Generate Release on host for portability, then sign with local GPG
size_of_file() {
  local f="$1"
  if stat -c %s "$f" >/dev/null 2>&1; then
    stat -c %s "$f"
  elif stat -f%z "$f" >/dev/null 2>&1; then
    stat -f%z "$f"
  else
    wc -c < "$f" | tr -d '[:space:]'
  fi
}

sha256_of_file() {
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" | awk '{print $1}'
  elif command -v ruby >/dev/null 2>&1; then
    ruby -rdigest -e 'puts Digest::SHA256.file(ARGV[0]).hexdigest' "$f"
  else
    echo "ERROR: need sha256sum, shasum, or ruby to compute SHA256" >&2
    return 1
  fi
}

release_file="$packaging_dir/debs/Release"
inrelease_file="$packaging_dir/debs/InRelease"
release_gpg_file="$packaging_dir/debs/Release.gpg"

# Compute a deterministic timestamp based on source tarball mtimes
input_tarball_x86="$packaging_dir/corkscrew-${version}-linux-x86_64.tar.gz"
input_tarball_arm="$packaging_dir/corkscrew-${version}-linux-arm64.tar.gz"

mtime_of_file() {
  local f="$1"
  if stat -c %Y "$f" >/dev/null 2>&1; then
    stat -c %Y "$f"
  elif stat -f %m "$f" >/dev/null 2>&1; then
    stat -f %m "$f"
  else
    # Fallback to current epoch if stat variant not available
    date +%s
  fi
}

format_rfc2822_utc() {
  local epoch="$1"
  if date -u -r "$epoch" "+%a, %d %b %Y %H:%M:%S +0000" >/dev/null 2>&1; then
    date -u -r "$epoch" "+%a, %d %b %Y %H:%M:%S +0000"
  elif date -u -d "@${epoch}" "+%a, %d %b %Y %H:%M:%S +0000" >/dev/null 2>&1; then
    date -u -d "@${epoch}" "+%a, %d %b %Y %H:%M:%S +0000"
  elif command -v ruby >/dev/null 2>&1; then
    ruby -e "puts Time.at(${epoch}).utc.strftime('%a, %d %b %Y %H:%M:%S +0000')"
  else
    date -u "+%a, %d %b %Y %H:%M:%S +0000"
  fi
}

src_epoch=0
if [[ -f "$input_tarball_x86" ]]; then
  e=$(mtime_of_file "$input_tarball_x86")
  (( e > src_epoch )) && src_epoch=$e || true
fi
if [[ -f "$input_tarball_arm" ]]; then
  e=$(mtime_of_file "$input_tarball_arm")
  (( e > src_epoch )) && src_epoch=$e || true
fi
if [[ $src_epoch -eq 0 ]]; then
  src_epoch=$(date +%s)
fi
release_date=$(format_rfc2822_utc "$src_epoch")

{
  echo 'Origin: corkscrew'
  echo 'Label: corkscrew'
  echo 'Suite: stable'
  echo 'Codename: stable'
  echo "Date: $release_date"
  echo 'Architectures: amd64 arm64'
  echo 'Components: main'
  echo 'Description: Corkscrew flat apt repo'
  echo 'SHA256:'
  for f in Packages Packages.gz; do
    if [[ -f "$packaging_dir/debs/$f" ]]; then
      sha=$(sha256_of_file "$packaging_dir/debs/$f")
      sz=$(size_of_file "$packaging_dir/debs/$f")
      printf ' %s %8d %s\n' "$sha" "$sz" "$f"
    fi
  done
} > "$release_file"

gpg --homedir "$packaging_dir/gpg" --batch --yes --pinentry-mode loopback --clearsign -o "$inrelease_file" "$release_file"
gpg --homedir "$packaging_dir/gpg" --batch --yes --pinentry-mode loopback -abs -o "$release_gpg_file" "$release_file"

# Verify metadata files exist for upload
for f in "$packaging_dir/debs/InRelease" "$packaging_dir/debs/Release" "$packaging_dir/debs/Release.gpg"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: expected metadata file missing: $f" >&2
  fi
done

echo
echo "Done!"



