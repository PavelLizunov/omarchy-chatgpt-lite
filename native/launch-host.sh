#!/usr/bin/bash -p
# Managed compatible host selector. Never run alongside a responding shell.
set -u
export PATH=/usr/bin:/bin LC_ALL=C
unset BASH_ENV CDPATH GLOBIGNORE
root="${HOME:?}/.local/share/omarchy-chatgpt-lite-host"
unit=omarchy-chatgpt-native-host.service
compatible() {
    local packages expected stock patched actual
    expected=$(/usr/bin/jq -er '.packages | strings' "$root/identity.json") || return 1
    packages=$(/usr/bin/timeout 5 /usr/bin/pacman -Q quickshell qt6-base qt6-declarative qt6-wayland qt6-webengine) || return 1
    [[ "$packages" == "$expected" ]] || return 1
    stock=$(/usr/bin/jq -er '.stock_sha256 | strings' "$root/identity.json") || return 1
    patched=$(/usr/bin/jq -er '.patched_sha256 | strings' "$root/identity.json") || return 1
    [[ "$stock" =~ ^[0-9a-f]{64}$ && "$patched" =~ ^[0-9a-f]{64}$ ]] || return 1
    actual=$(/usr/bin/timeout 5 /usr/bin/sha256sum /usr/bin/quickshell) || return 1
    [[ "${actual%% *}" == "$stock" ]] || return 1
    actual=$(/usr/bin/timeout 5 /usr/bin/sha256sum "$root/bin/quickshell") || return 1
    [[ "${actual%% *}" == "$patched" ]]
}
if [[ "${1:-}" == --guard && $# == 1 ]]; then compatible; exit $?; fi
[[ $# == 0 ]] || exit 2
fallback() { exec /usr/share/omarchy/bin/omarchy-launch-shell; }
if ! compatible; then
    printf '%s\n' 'Native host dependency drift: stock shell; incompatible browser open remains refused.' >&2
    fallback
fi
if /usr/bin/timeout 7 /usr/share/omarchy/bin/omarchy-shell shell ping >/dev/null 2>&1; then exit 0; fi
if /usr/bin/timeout 15 /usr/bin/systemctl --user start "$unit"; then
    deadline=$((SECONDS + 20))
    while (( SECONDS < deadline )); do
        if /usr/bin/timeout 7 /usr/share/omarchy/bin/omarchy-shell shell ping >/dev/null 2>&1; then exit 0; fi
        /usr/bin/sleep 0.2
    done
fi
# A failed stop blocks fallback, rather than admitting a second owner.
/usr/bin/timeout 15 /usr/bin/systemctl --user stop "$unit" || exit 1
fallback
