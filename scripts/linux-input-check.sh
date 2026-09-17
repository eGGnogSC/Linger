#!/usr/bin/env bash
# Native input comparison. No account, microphone, system install or live desktop.
set -euo pipefail

if [[ ${1:-} == --inside ]]; then
  [[ ${LINGER_PRIVATE_INPUT_DISPLAY:-} == 1 ]]
  [[ $XDG_RUNTIME_DIR == "$LINGER_INPUT_TMP/runtime" ]]
  [[ ${WLR_BACKENDS:-} == headless ]]
  export WEBKIT_DISABLE_DMABUF_RENDERER=1 NO_AT_BRIDGE=1
  # A headless seat needs a keyboard present between short-lived wtype calls.
  wtype -k Shift_L -s 120000 &
  input_keyboard_pid=$!
  trap 'kill "$input_keyboard_pid" 2>/dev/null || true' EXIT
  sleep 0.5
  for input_backend in wayland x11; do
    for input_surface in gtk webkit composer; do
      for input_mode in 1 30 clipboard; do
        result=0
        GDK_BACKEND="$input_backend" timeout --kill-after=2s 12s \
          "$LINGER_INPUT_TMP/input" "$input_surface" "$input_mode" || result=$?
        # Changed text in XWayland typing is the defect being diagnosed, not
        # a passing compatibility check. Clipboard and native Wayland must match.
        if (( result != 0 )); then
          [[ $result == 2 && $input_backend == x11 && $input_mode != clipboard ]] || exit "$result"
        fi
      done
    done
  done
  touch "$LINGER_INPUT_TMP/completed"
  exit 0
fi

[[ $# == 0 ]] || { echo "Usage: scripts/linux-input-check.sh" >&2; exit 1; }
for input_tool in cc pkg-config labwc Xwayland wtype wl-copy dbus-run-session timeout curl rg; do
  command -v "$input_tool" >/dev/null || { echo "Missing test tool: $input_tool" >&2; exit 1; }
done
pkg-config --exists webkit2gtk-4.1
input_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ -x "$input_repo/client/node_modules/.bin/vite" ]] || { echo "Install the client dev dependencies first." >&2; exit 1; }
input_tmp=$(mktemp -d /tmp/linger-native-input.XXXXXX)
input_vite_pid=
cleanup() {
  if [[ -n $input_vite_pid ]]; then kill "$input_vite_pid" 2>/dev/null || true; wait "$input_vite_pid" 2>/dev/null || true; fi
  rm -r -- "$input_tmp"
}
trap cleanup EXIT
mkdir -p "$input_tmp"/{runtime,config,data,state,cache}
chmod 700 "$input_tmp/runtime"
# pkg-config emits compiler flags; word splitting is intentional here.
# shellcheck disable=SC2046
cc -Wall -Wextra -Werror "$input_repo/scripts/linux-input-check.c" \
  -o "$input_tmp/input" $(pkg-config --cflags --libs webkit2gtk-4.1)
"$input_repo/client/node_modules/.bin/vite" "$input_repo/client" --host 127.0.0.1 --port 1422 --strictPort >"$input_tmp/vite.log" 2>&1 &
input_vite_pid=$!
input_ready=0
for ((attempt=0; attempt<50; attempt++)); do
  kill -0 "$input_vite_pid" 2>/dev/null || { echo "Fixture server failed; check that port 1422 is free." >&2; exit 1; }
  if curl -fsS http://127.0.0.1:1422/tests/fixtures/composer.html >/dev/null 2>&1; then input_ready=1; break; fi
  sleep 0.1
done
(( input_ready == 1 )) || { echo "Fixture server did not start." >&2; exit 1; }
printf -v input_session '%q --inside' "$input_repo/scripts/linux-input-check.sh"
result=0
env -u WAYLAND_DISPLAY -u WAYLAND_SOCKET -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
  -u DBUS_SESSION_BUS_ADDRESS -u GDK_BACKEND \
  XDG_RUNTIME_DIR="$input_tmp/runtime" XDG_CONFIG_HOME="$input_tmp/config" \
  XDG_CONFIG_DIRS="$input_tmp/config" XDG_DATA_HOME="$input_tmp/data" \
  XDG_STATE_HOME="$input_tmp/state" XDG_CACHE_HOME="$input_tmp/cache" \
  WLR_BACKENDS=headless WLR_RENDERER=pixman \
  LINGER_PRIVATE_INPUT_DISPLAY=1 LINGER_INPUT_TMP="$input_tmp" \
  dbus-run-session -- labwc -C "$input_tmp/config" -S "$input_session" \
  >"$input_tmp/result.log" 2>"$input_tmp/desktop.log" || result=$?
# Print only known fixture results, never desktop diagnostics or window metadata.
rg '^(wayland|x11) (gtk|webkit|composer) (1|30|clipboard): (MATCH|DIFFERENT)$' "$input_tmp/result.log" || true
if (( result != 0 )) || [[ ! -f $input_tmp/completed || $(wc -l < "$input_tmp/result.log") != 18 ]]; then
  echo "Input comparison incomplete or an expected control failed." >&2
  exit 1
fi
