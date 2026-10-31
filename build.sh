#!/bin/sh
# Build every device zip into dist/ (or only the devices given as arguments).
cd "$(dirname "$0")" && exec python3 build.py "$@"
