#!/usr/bin/env bash
set -euo pipefail


# Pushes the Homebrew formula to the GitHub repository.

# Config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_FORMULA="$SCRIPT_DIR/corkscrew_formula.rb"
DEST_REPO="windborne/homebrew-corkscrew"
DEST_PATH="Formula/corkscrew-deploys.rb"
BRANCH="main"

# Requires a GitHub token with repo write access
# Load from .env if not already set
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  if [[ -f "$SCRIPT_DIR/../.env" ]]; then
    set -a
    source "$SCRIPT_DIR/../.env"
    set +a
  elif [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
  fi
fi
: "${GITHUB_TOKEN:?Need to set GITHUB_TOKEN}"

# Verify version consistency between formula and Ruby gem
RUBY_VERSION_FILE="$SCRIPT_DIR/../corkscrew/version.rb"
if [[ ! -f "$RUBY_VERSION_FILE" ]]; then
  echo "Version file not found: $RUBY_VERSION_FILE" >&2
  exit 1
fi

FORMULA_VERSION="$(awk -F"'" '/VERSION *=/{print $2}' "$SRC_FORMULA" | tr -d '[:space:]')"
RUBY_VERSION="$(awk -F"'" '/VERSION *=/{print $2}' "$RUBY_VERSION_FILE" | tr -d '[:space:]')"

if [[ -z "$FORMULA_VERSION" || -z "$RUBY_VERSION" ]]; then
  echo "Failed to extract version from files" >&2
  exit 1
fi

if [[ "$FORMULA_VERSION" != "$RUBY_VERSION" ]]; then
  echo "Version mismatch: formula=$FORMULA_VERSION ruby=$RUBY_VERSION" >&2
  exit 1
fi

# Announce version being uploaded
echo "Uploading Homebrew formula version $FORMULA_VERSION to $DEST_REPO/$DEST_PATH (branch: $BRANCH)"

# Read file content and base64 encode
CONTENT_B64=$(base64 -i "$SRC_FORMULA" | tr -d '\n')

# Get current file SHA if it exists
API_URL="https://api.github.com/repos/$DEST_REPO/contents/$DEST_PATH?ref=$BRANCH"
FILE_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$API_URL" | jq -r '.sha // empty')

# Build JSON payload
if [[ -n "$FILE_SHA" ]]; then
  echo "Updating existing formula..."
  JSON=$(jq -n \
    --arg msg "Update corkscrew formula to v$FORMULA_VERSION" \
    --arg content "$CONTENT_B64" \
    --arg branch "$BRANCH" \
    --arg sha "$FILE_SHA" \
    '{message:$msg, content:$content, branch:$branch, sha:$sha}')
else
  echo "Creating new formula..."
  JSON=$(jq -n \
    --arg msg "Create corkscrew formula v$FORMULA_VERSION" \
    --arg content "$CONTENT_B64" \
    --arg branch "$BRANCH" \
    '{message:$msg, content:$content, branch:$branch}')
fi

# Upload via GitHub API and show concise result
RESP_FILE=$(mktemp)
HTTP_STATUS=$(curl -s -o "$RESP_FILE" -w "%{http_code}" -X PUT \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$JSON" \
  "https://api.github.com/repos/$DEST_REPO/contents/$DEST_PATH")

if [[ "$HTTP_STATUS" =~ ^2 ]]; then
  echo "Upload successful (HTTP $HTTP_STATUS)"
else
  echo "Upload failed (HTTP $HTTP_STATUS)" >&2
fi

rm -f "$RESP_FILE"