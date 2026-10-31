#!/bin/sh
# Release every device in one GitHub release (tag vX.Y.Z from the VERSION file).
# usage: ./release.sh [--dry-run]
cd "$(dirname "$0")" && exec python3 tools/release.py "$@"
