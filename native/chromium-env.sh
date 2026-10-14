#!/usr/bin/bash -p
# Startup policy for the caller's managed host; exec preserves its process owner.
set -eu
if (( $# == 0 )); then
    printf '%s\n' 'Usage: chromium-env.sh HOST [ARGUMENT ...]' >&2
    exit 64
fi
export CHATGPT_LITE_ENGINE=chromium
export QTWEBENGINE_CHROMIUM_FLAGS="${QTWEBENGINE_CHROMIUM_FLAGS:+$QTWEBENGINE_CHROMIUM_FLAGS }--site-per-process"
exec "$@"
