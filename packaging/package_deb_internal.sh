#!/usr/bin/env bash
set -euo pipefail

: "${VERSION:?VERSION env var required}"
: "${TAR_PATH:?TAR_PATH env var required}"
ARCH_DPKG="${ARCH:-}"
# Package identity vs installed binary/lib names
PACKAGE_NAME="${PACKAGE_NAME:-corkscrew}"
BIN_NAME="${BIN_NAME:-corkscrew}"
LIB_DIR_NAME="${LIB_DIR_NAME:-corkscrew}"
GPG_DIR="${GPG_DIR:-}"
GPG_KEY_ID="${GPG_KEY_ID:-}"
SIGN_DEBS="${SIGN_DEBS:-}"

# Reproducible-build settings: derive SOURCE_DATE_EPOCH from input tarball mtime
if [[ -z "${SOURCE_DATE_EPOCH:-}" ]]; then
  if stat -c %Y "${TAR_PATH}" >/dev/null 2>&1; then
    export SOURCE_DATE_EPOCH="$(stat -c %Y "${TAR_PATH}")"
  elif stat -f %m "${TAR_PATH}" >/dev/null 2>&1; then
    export SOURCE_DATE_EPOCH="$(stat -f %m "${TAR_PATH}")"
  else
    export SOURCE_DATE_EPOCH="$(date +%s)"
  fi
fi
export GZIP="-n"
export LC_ALL=C
export TZ=UTC

if [[ -z "${ARCH_DPKG}" ]]; then
  if [[ "${TAR_PATH}" =~ linux-x86_64\.tar\.gz$ ]]; then
    ARCH_DPKG=amd64
  elif [[ "${TAR_PATH}" =~ linux-arm64\.tar\.gz$ ]]; then
    ARCH_DPKG=arm64
  else
    echo "ERROR: Unable to infer ARCH from TAR_PATH; set ARCH explicitly (amd64/arm64)." >&2
    exit 1
  fi
fi

mkdir -p /staging/usr/bin /staging/usr/lib/${LIB_DIR_NAME}

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

# Extract input tarball and determine source root containing 'corkscrew' and 'lib/'
# Suppress warnings about unknown pax keywords (e.g., LIBARCHIVE.xattr.*)
tar --warning=no-unknown-keyword -C "${TMPDIR}" -xzf "${TAR_PATH}"

SRC_DIR="${TMPDIR}"
if [[ ! -f "${SRC_DIR}/corkscrew" || ! -d "${SRC_DIR}/lib" ]]; then
  if [[ -d "${TMPDIR}/corkscrew" ]]; then
    SRC_DIR="${TMPDIR}/corkscrew"
  else
    mapfile -t _dirs < <(find "${TMPDIR}" -mindepth 1 -maxdepth 1 -type d)
    if [[ ${#_dirs[@]} -eq 1 ]]; then
      SRC_DIR="${_dirs[0]}"
    fi
  fi
fi

if [[ ! -f "${SRC_DIR}/corkscrew" || ! -d "${SRC_DIR}/lib" ]]; then
  echo "ERROR: Tarball missing expected entries: corkscrew and lib/ at root." >&2
  echo "TMPDIR contents:" >&2
  ls -la "${TMPDIR}" >&2 || true
  echo "SRC_DIR considered: ${SRC_DIR}" >&2
  ls -la "${SRC_DIR}" >&2 || true
  exit 1
fi

install -m 0755 "${SRC_DIR}/corkscrew" /staging/usr/bin/${BIN_NAME}
cp -a "${SRC_DIR}/lib" /staging/usr/lib/${LIB_DIR_NAME}/

# Ensure wrapper uses system lib path
sed -i "s|^SELFDIR=.*|SELFDIR=\"/usr/lib/${LIB_DIR_NAME}\"|" /staging/usr/bin/${BIN_NAME}

# Normalize mtimes to SOURCE_DATE_EPOCH for reproducibility
find /staging -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} + 2>/dev/null || true

# Build the .deb
fpm -s dir -t deb \
  -n "${PACKAGE_NAME}" \
  -v "${VERSION}" \
  -a "${ARCH_DPKG}" \
  --deb-user root \
  --deb-group root \
  --deb-compression gz \
  --description "Deploy and run code on another machine" \
  --license "MIT" \
  --maintainer "Windborne" \
  --url "https://github.com/windborne/corkscrew" \
  --deb-no-default-config-files \
  -C /staging \
  usr/bin/${BIN_NAME} \
  usr/lib/${LIB_DIR_NAME}

mkdir -p /out
shopt -s nullglob
for f in *.deb; do
  mv "$f" /out/
  echo "Built: /out/$(basename "$f")"
done

# Optionally sign output packages if GPG key is provided (using debsigs)
if [[ "${SIGN_DEBS}" = "1" && -n "${GPG_DIR}" && -d "${GPG_DIR}" ]]; then
  echo "Signing .deb with GPG keyring from ${GPG_DIR} (debsigs)"
  # Import key(s)
  gpg --batch --import "${GPG_DIR}"/*.asc 2>/dev/null || true
  gpg --batch --import "${GPG_DIR}"/*.gpg 2>/dev/null || true
  gpg --batch --import "${GPG_DIR}"/*.key 2>/dev/null || true
  gpg --batch --import "${GPG_DIR}"/*.pub 2>/dev/null || true
  if compgen -G "${GPG_DIR}/*.sec" > /dev/null; then
    gpg --batch --import "${GPG_DIR}"/*.sec || true
  fi

  signer="${GPG_KEY_ID:-}"
  if [[ -z "$signer" ]]; then
    signer=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')
  fi

  if [[ -z "$signer" ]]; then
    echo "WARNING: No GPG signing key found; skipping signing." >&2
  else
    for deb in /out/*.deb; do
      echo "Signing $deb with debsigs (key $signer)"
      debsigs --sign=origin --verify --check -k "$signer" "$deb" || debsigs --sign=origin -k "$signer" "$deb" || {
        echo "WARNING: debsigs failed for $deb; package left unsigned." >&2
      }
    done
  fi
fi


