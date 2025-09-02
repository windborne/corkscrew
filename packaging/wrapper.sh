#!/bin/bash
set -e

# Figure out where this script is located.
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

# If the lib directory doesn't exist, adjust to the parent directory -- brew forces a certain directory structure
if [ ! -d "$SELFDIR/lib" ]; then
  SELFDIR="$SELFDIR/.."
fi

# Tell Bundler where the Gemfile and gems are.
export BUNDLE_GEMFILE="$SELFDIR/lib/vendor/Gemfile"
unset BUNDLE_IGNORE_CONFIG

export BUNDLE_FROZEN=1
export BUNDLE_DEPLOYMENT=1

# Run the actual app using the bundled Ruby interpreter, with Bundler activated.
exec "$SELFDIR/lib/ruby/bin/ruby" -rbundler/setup "$SELFDIR/lib/app/corkscrew.rb" $@
