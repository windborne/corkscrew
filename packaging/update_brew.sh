#!/usr/bin/env bash
set -euo pipefail

# Update Homebrew formula sha256s and version based on local packaging artifacts
# - Reads version from corkscrew/version.rb
# - Computes sha256 for packaging/corkscrew-<version>-osx-{x86_64,arm64}.tar.gz
# - Updates packaging/corkscrew_formula.rb VERSION and sha256 lines in-place

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version_file="$repo_root/corkscrew/version.rb"
formula_file="$repo_root/packaging/corkscrew_formula.rb"
packaging_dir="$repo_root/packaging"

if [[ ! -f "$version_file" ]]; then
  echo "ERROR: Version file not found: $version_file" >&2
  exit 1
fi

if [[ ! -f "$formula_file" ]]; then
  echo "ERROR: Formula file not found: $formula_file" >&2
  exit 1
fi

# Extract version from corkscrew/version.rb (expects: VERSION = 'x.y.z')
version="$(awk -F"'" '/VERSION *=/{print $2}' "$version_file" | tr -d '[:space:]')"
if [[ -z "$version" ]]; then
  echo "ERROR: Could not parse version from $version_file" >&2
  exit 1
fi

artifact_x86="$packaging_dir/corkscrew-$version-osx-x86_64.tar.gz"
artifact_arm="$packaging_dir/corkscrew-$version-osx-arm64.tar.gz"

for f in "$artifact_x86" "$artifact_arm"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Expected artifact not found: $f" >&2
    exit 1
  fi
done

sha_x86="$(shasum -a 256 "$artifact_x86" | awk '{print $1}')"
sha_arm="$(shasum -a 256 "$artifact_arm" | awk '{print $1}')"

if [[ -z "$sha_x86" || -z "$sha_arm" ]]; then
  echo "ERROR: Failed to compute sha256 for one or more artifacts" >&2
  exit 1
fi

# sed -i portability between GNU and BSD (macOS)
sed_in_place() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# 1) Update VERSION constant at top of formula
sed_in_place -E "s/^(VERSION *= *')[^']*(')/\\1$version\\2/" "$formula_file"

# 2) Update sha256 values in the appropriate conditional blocks
# We anchor on the URL lines that contain arch-specific filenames, then update
# the next sha256 line in that block.
awk -v sha_x86="$sha_x86" -v sha_arm="$sha_arm" '
  BEGIN { in_x86=0; in_arm=0 }
  /-osx-x86_64\.tar\.gz/ { in_x86=1; in_arm=0 }
  /-osx-arm64\.tar\.gz/ { in_arm=1; in_x86=0 }
  {
    if (in_x86 && $0 ~ /^[[:space:]]*sha256[[:space:]]*"/) {
      sub(/sha256[[:space:]]*"[0-9a-fA-F]+"/, "sha256 \"" sha_x86 "\"")
      in_x86=0
    } else if (in_arm && $0 ~ /^[[:space:]]*sha256[[:space:]]*"/) {
      sub(/sha256[[:space:]]*"[0-9a-fA-F]+"/, "sha256 \"" sha_arm "\"")
      in_arm=0
    }
    print
  }
' "$formula_file" > "$formula_file.tmp" && mv "$formula_file.tmp" "$formula_file"

echo "Updated $formula_file:"
echo "  VERSION = $version"
echo "  osx-x86_64 sha256 = $sha_x86"
echo "  osx-arm64  sha256 = $sha_arm"

