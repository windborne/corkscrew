#!/usr/bin/env bash
set -euo pipefail

# Creates the version tag and GitHub release, then uploads the four versioned
# Linux/macOS tarballs. Reruns keep an existing tag/release and upload only
# assets that are missing.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
packaging_dir="$repo_root/packaging"
version_file="$repo_root/corkscrew/version.rb"

# Keep gh repository detection working when this script is invoked from outside
# the repository.
cd "$repo_root"

check_only=false

usage() {
  echo "Usage: bash packaging/create_github_release.sh [--check]" >&2
}

if [[ $# -gt 1 ]]; then
  usage
  exit 2
fi

if [[ $# -eq 1 ]]; then
  case "$1" in
    --check)
      check_only=true
      ;;
    *)
      usage
      exit 2
      ;;
  esac
fi

die() {
  echo "ERROR: $*" >&2
  exit 1
}

for command_name in git gh; do
  command -v "$command_name" >/dev/null 2>&1 ||
    die "$command_name is required"
done

[[ -f "$version_file" ]] ||
  die "Version file not found: $version_file"

version="$(awk -F"'" '/VERSION *=/{print $2}' "$version_file" | tr -d '[:space:]')"
[[ -n "$version" ]] ||
  die "Could not parse version from $version_file"

tag="v$version"
commit="$(git -C "$repo_root" rev-parse HEAD)"
committed_version="$(
  git -C "$repo_root" show "HEAD:corkscrew/version.rb" |
    awk -F"'" '/VERSION *=/{print $2}' |
    tr -d '[:space:]'
)"

if [[ "$committed_version" != "$version" ]]; then
  die "corkscrew/version.rb has an uncommitted version change. Commit version $version before releasing so $tag points to the correct source."
fi

artifacts=(
  "$packaging_dir/corkscrew-$version-linux-arm64.tar.gz"
  "$packaging_dir/corkscrew-$version-linux-x86_64.tar.gz"
  "$packaging_dir/corkscrew-$version-osx-arm64.tar.gz"
  "$packaging_dir/corkscrew-$version-osx-x86_64.tar.gz"
)

for artifact in "${artifacts[@]}"; do
  [[ -f "$artifact" ]] ||
    die "Expected release artifact not found: $artifact"
done

gh auth status >/dev/null 2>&1 ||
  die "GitHub CLI authentication failed. Run 'gh auth login' or provide GH_TOKEN/GITHUB_TOKEN."

local_tag_commit="$(git -C "$repo_root" rev-list -n 1 "$tag" 2>/dev/null || true)"
if [[ -n "$local_tag_commit" && "$local_tag_commit" != "$commit" ]]; then
  die "Local tag $tag points to $local_tag_commit, not HEAD ($commit)"
fi

if ! remote_refs="$(
  git -C "$repo_root" ls-remote --tags origin \
    "refs/tags/$tag" "refs/tags/$tag^{}"
)"; then
  die "Could not inspect tag $tag on origin"
fi

remote_tag_commit="$(
  printf '%s\n' "$remote_refs" |
    awk -v ref="refs/tags/$tag" '
      $2 == ref { direct = $1 }
      $2 == ref "^{}" { peeled = $1 }
      END {
        if (peeled != "") print peeled
        else if (direct != "") print direct
      }
    '
)"

if [[ -n "$remote_tag_commit" && "$remote_tag_commit" != "$commit" ]]; then
  die "Remote tag $tag points to $remote_tag_commit, not HEAD ($commit)"
fi

if [[ "$check_only" == true ]]; then
  echo "GitHub release prerequisites passed for $tag at $commit"
  exit 0
fi

if [[ -z "$local_tag_commit" ]]; then
  echo "Creating local tag $tag at $commit"
  git -C "$repo_root" tag "$tag" "$commit"
else
  echo "Local tag $tag already points to $commit"
fi

if [[ -z "$remote_tag_commit" ]]; then
  echo "Pushing tag $tag to origin"
  git -C "$repo_root" push origin "refs/tags/$tag"
else
  echo "Remote tag $tag already points to $commit"
fi

if gh release view "$tag" --json tagName >/dev/null 2>&1; then
  echo "GitHub release $tag already exists"

  existing_assets="$(gh release view "$tag" --json assets --jq '.assets[].name')"
  missing_artifacts=()

  for artifact in "${artifacts[@]}"; do
    artifact_name="$(basename "$artifact")"
    if ! grep -Fqx -- "$artifact_name" <<<"$existing_assets"; then
      missing_artifacts+=( "$artifact" )
    fi
  done

  if [[ ${#missing_artifacts[@]} -gt 0 ]]; then
    echo "Uploading ${#missing_artifacts[@]} missing release asset(s)"
    gh release upload "$tag" "${missing_artifacts[@]}"
  else
    echo "All release assets are already uploaded"
  fi

  if [[ "$(gh release view "$tag" --json isDraft --jq '.isDraft')" == true ]]; then
    echo "Publishing draft release $tag"
    gh release edit "$tag" --draft=false
  fi
else
  echo "Creating GitHub release $tag and uploading ${#artifacts[@]} assets"
  gh release create "$tag" "${artifacts[@]}" \
    --verify-tag \
    --title "$tag" \
    --notes ""
fi

release_url="$(gh release view "$tag" --json url --jq '.url')"
echo "GitHub release published: $release_url"
