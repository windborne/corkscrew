#!/bin/bash
set -euo pipefail

# Upload all corkscrew-*.tar.gz files in this directory to
# s3://wb-data-public/corkscrew/ with public-read ACL.
# Idempotent: skips upload when the remote object matches the local file MD5.
# AWS credentials/region are loaded from .env in this directory if present.

# Resolve this script's directory (matches style used in wrapper.sh)
realpath() {
  OURPWD=$PWD
  cd "$(dirname "$1")"
  LINK=$(readlink "$(basename "$1")")
  while [ "$LINK" ]; do
    cd "$(dirname "$LINK")"
    LINK=$(readlink "$(basename "$1")")
  done
  REALPATH="$PWD/$(basename "$1")"
  cd "$OURPWD"
  echo "$REALPATH"
}

SELFDIR=$( dirname $(realpath "$0") )
SELFDIR="`cd -P \"$SELFDIR\" && pwd`"

ENV_FILE="$SELFDIR/.env"

# Load AWS_* from .env if present
if [ -f "$ENV_FILE" ]; then
  # Export variables defined in .env
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

# Map S3_* aliases to AWS_* if provided, and ensure exports
if [ -n "${S3_ACCESS_KEY_ID:-}" ] && [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
  export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
fi
if [ -n "${S3_SECRET_ACCESS_KEY:-}" ] && [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
fi
if [ -n "${S3_SESSION_TOKEN:-}" ] && [ -z "${AWS_SESSION_TOKEN:-}" ]; then
  export AWS_SESSION_TOKEN="$S3_SESSION_TOKEN"
fi
if [ -n "${S3_REGION:-}" ] && [ -z "${AWS_REGION:-}" ] && [ -z "${AWS_DEFAULT_REGION:-}" ]; then
  export AWS_REGION="$S3_REGION"
fi

# Ensure variables are exported if already set by the environment/.env
[ -n "${AWS_ACCESS_KEY_ID:-}" ] && export AWS_ACCESS_KEY_ID
[ -n "${AWS_SECRET_ACCESS_KEY:-}" ] && export AWS_SECRET_ACCESS_KEY
[ -n "${AWS_SESSION_TOKEN:-}" ] && export AWS_SESSION_TOKEN
[ -n "${AWS_PROFILE:-}" ] && export AWS_PROFILE

# Prefer AWS_REGION, fallback to AWS_DEFAULT_REGION, default to us-east-1
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
export AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: aws CLI is required. Install via 'brew install awscli' or similar." >&2
  exit 1
fi

# Parse flags
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
  esac
done

if [ "$DRY_RUN" = true ]; then
  echo "Dry run: no uploads will be performed"
fi

# Compute lowercase MD5 hex of a file, portable across macOS/Linux
md5_of_file() {
  local file="$1"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$file" | awk '{print tolower($1)}'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$file" | tr '[:upper:]' '[:lower:]'
  elif command -v ruby >/dev/null 2>&1; then
    ruby -rdigest -e 'f=ARGV[0]; puts Digest::MD5.file(f).hexdigest' "$file"
  else
    echo "Error: need md5sum, md5, or ruby available to compute MD5." >&2
    exit 1
  fi
}

BUCKET="wb-data-public"
PREFIX="corkscrew"

# Return remote ETag (lowercase, without quotes) for s3://$BUCKET/$key,
# or empty string if object does not exist.
get_remote_etag() {
  local key="$1"
  local etag=""
  # Avoid exiting on 404 under set -e
  set +e
  etag=$(aws s3api head-object \
    --bucket "$BUCKET" \
    --key "$key" \
    --query ETag \
    --output text 2>/dev/null)
  local status=$?
  set -e
  if [ $status -ne 0 ] || [ "$etag" = "None" ]; then
    echo ""
    return 0
  fi
  echo "$etag" | tr -d '"' | tr '[:upper:]' '[:lower:]'
}

# Find artifacts
shopt -s nullglob
artifacts=( "$SELFDIR"/corkscrew-*.tar.gz )

if [ ${#artifacts[@]} -eq 0 ]; then
  echo "No artifacts found matching $SELFDIR/corkscrew-*.tar.gz"
  exit 0
fi

for file in "${artifacts[@]}"; do
  basename=$(basename "$file")
  key="$PREFIX/$basename"

  local_md5=$(md5_of_file "$file")
  remote_etag=$(get_remote_etag "$key")

  # Determine whether this is a LATEST artifact
  is_latest=false
  if [[ "$basename" == *LATEST* ]]; then
    is_latest=true
  fi

  if [ -n "$remote_etag" ]; then
    if [ "$is_latest" = true ]; then
      if [ "$remote_etag" = "$local_md5" ]; then
        echo "Skipping $basename: remote matches local (ETag=$remote_etag)"
        continue
      fi
      if [ "$DRY_RUN" = true ]; then
        echo "Overwriting $basename: existing LATEST object at s3://$BUCKET/$key"
        continue
      fi
      echo "Overwriting $basename: existing LATEST object at s3://$BUCKET/$key ..."
    else
      echo "Skipping $basename: remote exists and artifact is versioned (not overwriting)"
      continue
    fi
  else
    if [ "$DRY_RUN" = true ]; then
      echo "Uploading $basename: new object to s3://$BUCKET/$key"
      continue
    fi
    echo "Uploading $basename: new object to s3://$BUCKET/$key ..."
  fi

  # Use s3api put-object to ensure single-part upload so ETag==MD5
  aws s3api put-object \
    --bucket "$BUCKET" \
    --key "$key" \
    --body "$file" \
    --acl public-read \
    --content-type application/gzip >/dev/null

  # Verify upload by checking ETag again
  new_etag=$(get_remote_etag "$key")
  if [ "$new_etag" = "$local_md5" ]; then
    echo "  Uploaded OK (ETag=$new_etag)"
  else
    echo "  Note: ETag after upload is $new_etag (expected MD5 $local_md5)" >&2
  fi
done

echo "Done."


