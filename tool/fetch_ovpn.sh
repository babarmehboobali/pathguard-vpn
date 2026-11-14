#!/usr/bin/env bash
# Fetches the ics-openvpn engine (pinned version) into android/ovpn.
# Run from the project root before building: ./tool/fetch_ovpn.sh
set -euo pipefail
REV=660901ce320539aec476bd04bd1999c396d5e778
DIR=android/ovpn
if [ ! -d "$DIR/.git" ]; then
  git clone https://github.com/schwabe/ics-openvpn.git "$DIR"
fi
git -C "$DIR" fetch --depth 1 origin "$REV"
git -C "$DIR" checkout -q "$REV"
git -C "$DIR" submodule update --init --recursive --depth 1
