#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"
python -m http.server 8124
