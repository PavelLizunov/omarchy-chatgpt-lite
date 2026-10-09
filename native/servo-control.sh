#!/usr/bin/bash -p
set -euo pipefail
export PATH=/usr/bin:/bin LC_ALL=C
unset BASH_ENV CDPATH GLOBIGNORE
# Only the task-owned engine is managed; no shell or profile operation.
case "${1:-}" in start|restart|stop) action="$1";; *) exit 64;; esac
unit=chatgpt-servo-engine.service
base="${XDG_RUNTIME_DIR:?}"
[[ "$base" == /* && -d "$base" && ! -L "$base" && $(stat -c '%u:%a' "$base") == "$UID:700" ]] || exit 65
runtime="$base/chatgpt-servo-native"
if [[ ! -e "$runtime" && ! -L "$runtime" ]]; then mkdir -m 700 -- "$runtime"; fi
[[ -d "$runtime" && ! -L "$runtime" && $(stat -c '%u:%a' "$runtime") == "$UID:700" ]] || exit 65
timeout 18 systemctl --user "$action" "$unit"
[[ "$action" == stop ]] && exit 0
for ((i=0; i<100; i++)); do
    if [[ -S "$runtime/native.sock" && ! -L "$runtime/native.sock" && $(stat -c '%u:%a' "$runtime/native.sock") == "$UID:600" ]]; then
        systemctl --user is-active --quiet "$unit" && exit 0
    fi
    sleep 0.1
done
exit 66
