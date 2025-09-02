#!/bin/bash
set -euo pipefail

# Installs the Homebrew formula locally.
# - Sets up a local formula directory, with the local tarball
# - Installs the formula
# - If --package is passed, builds the arm64 tarball via `rake package:osx:arm64`

# Resolve repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION_FILE="$REPO_ROOT/corkscrew/version.rb"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "ERROR: Version file not found: $VERSION_FILE" >&2
  exit 1
fi

# Optional packaging step
if [[ "${1:-}" == "--package" ]]; then
  echo "Packaging arm64 tarball via rake ..."
  (cd "$REPO_ROOT" && rake package:osx:arm64 | cat)
fi

# Extract version from corkscrew/version.rb (expects: VERSION = 'x.y.z')
VERSION="$(awk -F"'" '/VERSION *=/{print $2}' "$VERSION_FILE" | tr -d '[:space:]')"
if [[ -z "$VERSION" ]]; then
  echo "ERROR: Could not parse version from $VERSION_FILE" >&2
  exit 1
fi

ARTIFACT_X86="$REPO_ROOT/packaging/corkscrew-$VERSION-osx-x86_64.tar.gz"
ARTIFACT_ARM="$REPO_ROOT/packaging/corkscrew-$VERSION-osx-arm64.tar.gz"

for f in "$ARTIFACT_X86" "$ARTIFACT_ARM"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Expected artifact not found: $f" >&2
    echo "       Build or place the tarballs under packaging/ first." >&2
    exit 1
  fi
done

SHA_X86="$(shasum -a 256 "$ARTIFACT_X86" | awk '{print $1}')"
SHA_ARM="$(shasum -a 256 "$ARTIFACT_ARM" | awk '{print $1}')"

if [[ -z "$SHA_X86" || -z "$SHA_ARM" ]]; then
  echo "ERROR: Failed to compute sha256 for one or more artifacts" >&2
  exit 1
fi

# Ensure the tap exists; create if missing
TAP="kai/local"
if ! brew tap-info "$TAP" >/dev/null 2>&1; then
  echo "Creating local tap $TAP ..."
  brew tap-new "$TAP" >/dev/null
fi

TAP_DIR="$(brew --repo "$TAP")"
FORMULA_DIR="$TAP_DIR/Formula"
FORMULA_PATH="$FORMULA_DIR/corkscrew-deploys.rb"
mkdir -p "$FORMULA_DIR"

# Write a local formula that references file:// URLs for both architectures
cat > "$FORMULA_PATH" <<EOF
VERSION = '$VERSION'

class CorkscrewDeploys < Formula
  desc "Deploy and run code on another machine"
  homepage "https://github.com/windborne/corkscrew"
  version VERSION

  if Hardware::CPU.intel?
    url "file://$ARTIFACT_X86"
    sha256 "$SHA_X86"
  else
    url "file://$ARTIFACT_ARM"
    sha256 "$SHA_ARM"
  end

  def install
    bin.install "corkscrew"
    lib.install Dir["lib/*"]
  end

  test do
    system "#{bin}/corkscrew", "--version"
  end
end
EOF

echo "Wrote local formula to: $FORMULA_PATH"

echo "Fetching fresh artifact via Homebrew ..."
brew fetch --force kai/local/corkscrew-deploys | cat

echo "Reinstalling via Homebrew from local formula ..."
brew reinstall kai/local/corkscrew-deploys | cat

echo "Done. Running corkscrew --version"
corkscrew --version
