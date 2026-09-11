#!/bin/sh
# setup.sh - install / uninstall / check / test the bt-sane Bluetooth UX suite:
# bt-le (the LE/passkey toggle) + bt-indicator (a passive SNI tray icon). The
# SINGLE entry point a consumer or provisioning layer uses.
#
#   ./setup.sh install     link bt-le (+ man) into ~/.local
#   ./setup.sh service     build the tray-icon venv + enable its --user daemon
#   ./setup.sh all         install + service
#   ./setup.sh uninstall   remove the links + the --user daemon
#   ./setup.sh check       tools + deps present; [OK]/[FAIL] markers
#   ./setup.sh test        run the in-repo suite (test/run)
#   ./setup.sh version     the packaged version
#
# POSIX sh, non-privileged. `install` is bt-le + man ONLY (the contract a
# provisioner delegates to); the tray icon is a Python/dbus daemon, so it is a
# separate `service` verb (builds a venv, no venv-run dependency). bt-le is a
# ROOT helper in use (it edits /etc/bluetooth/main.conf + restarts bluetooth);
# `install` links it for `bt-le status` by hand -- an integrator installs it to
# a root path with a narrow NOPASSWD grant (that privileged step is not here).
set -eu

PKG=bt-sane
VERSION=0.1.0
_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ -z "${HOME:-}" ]; then
  HOME=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)
  if [ -z "$HOME" ]; then
    echo "$PKG: HOME unset and not derivable from passwd" >&2; exit 1
  fi
  export HOME
fi

PREFIX=${PREFIX:-$HOME/.local}
_bin=${XDG_BIN_HOME:-$PREFIX/bin}
_shr=${XDG_DATA_HOME:-$PREFIX/share}
_man=$_shr/man
_cfg=${XDG_CONFIG_HOME:-$HOME/.config}
_usr=$_cfg/systemd/user
VENV=${BT_SANE_VENV:-$HOME/.venvs/bt-sane}
DEPS="bluetoothd"                    # bluez daemon; the mount of the suite
DEPS_SOFT="blueman-manager python3"  # blueman = the right-click manager
RC=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  _G=$(printf '\033[32m'); _R=$(printf '\033[31m')
  _Y=$(printf '\033[33m'); _O=$(printf '\033[0m')
else _G=; _R=; _Y=; _O=; fi
ok()   { printf '  %s[OK]%s   %s\n' "$_G" "$_O" "$1"; }
bad()  { printf '  %s[FAIL]%s %s\n' "$_R" "$_O" "$1"; RC=1; }
warn() { printf '  %s[WARN]%s %s\n' "$_Y" "$_O" "$1"; }

_man_pages() { for _m in "$_root"/man/man*/*.[0-9]; do
  [ -e "$_m" ] && printf '%s\n' "$_m"; done; }

do_install() {
  mkdir -p "$_bin"
  ln -sfn "$_root/libexec/bt-le" "$_bin/bt-le"
  _man_pages | while IFS= read -r _m; do
    _d=$_man/$(basename "$(dirname "$_m")")
    mkdir -p "$_d"; ln -sfn "$_m" "$_d/$(basename "$_m")"; done
  echo "$PKG: linked bt-le (+ man) into $PREFIX"
}

do_service() {
  command -v python3 >/dev/null 2>&1 || {
    echo "$PKG: python3 absent; no tray-icon venv" >&2; return 1; }
  [ -d "$VENV" ] || python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q -r "$_root/libexec/bt-indicator.reqs"
  # A launcher: exec the venv python on the packaged daemon (replaces venv-run;
  # this launcher is the only thing the daemon needs on PATH).
  mkdir -p "$_bin"
  cat > "$_bin/bt-indicator" <<EOF
#!/bin/sh
exec "$VENV/bin/python" "$_root/libexec/bt-indicator" "\$@"
EOF
  chmod +x "$_bin/bt-indicator"
  mkdir -p "$_usr"
  cp "$_root/systemd/bt-indicator.service" "$_usr/bt-indicator.service"
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable bt-indicator.service 2>/dev/null || true
  systemctl --user restart bt-indicator.service 2>/dev/null || true
  echo "$PKG: bt-indicator venv + --user daemon installed + enabled"
}

do_uninstall() {
  for _l in "$_bin/bt-le" "$_bin/bt-indicator"; do
    [ -e "$_l" ] && rm -f "$_l" || :; done
  _man_pages | while IFS= read -r _m; do
    _l=$_man/$(basename "$(dirname "$_m")")/$(basename "$_m")
    [ "$(readlink "$_l" 2>/dev/null)" = "$_m" ] && rm -f "$_l" || :; done
  if [ -e "$_usr/bt-indicator.service" ]; then
    systemctl --user disable --now bt-indicator.service 2>/dev/null || true
    rm -f "$_usr/bt-indicator.service"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  echo "$PKG: removed the links + the daemon (venv left)"
}

do_check() {
  echo "== $PKG (bluetooth tray + LE toggle) =="
  if [ "$(readlink "$_bin/bt-le" 2>/dev/null)" = "$_root/libexec/bt-le" ]; then
    ok "bt-le linked"
  else bad "bt-le not linked ($_bin/bt-le)"; fi
  for _d in $DEPS; do
    command -v "$_d" >/dev/null 2>&1 && ok "dep $_d present" \
      || warn "dep $_d absent (bluez -- the suite needs it)"; done
  for _d in $DEPS_SOFT; do
    command -v "$_d" >/dev/null 2>&1 && ok "dep $_d present" \
      || warn "dep $_d absent (a feature degrades)"; done
  # the tray daemon is opt-in (`service`); audit it only once installed
  if [ -e "$_bin/bt-indicator" ]; then
    [ -x "$VENV/bin/python" ] && ok "tray venv present" \
      || bad "tray launcher present but venv missing (setup.sh service)"
    systemctl --user is-enabled --quiet bt-indicator.service 2>/dev/null \
      && ok "bt-indicator.service enabled" \
      || bad "bt-indicator.service not enabled (setup.sh service)"
  else
    warn "tray icon not installed (run setup.sh service for it)"
  fi
}

_U="usage: setup.sh [install|service|all|uninstall|check|test|version]"
case "${1:-install}" in
  install)   do_install ;;
  service)   do_service ;;
  all)       do_install; do_service ;;
  uninstall) do_uninstall ;;
  check)     do_check; exit "$RC" ;;
  test)      exec sh "$_root/test/run" ;;
  version)   echo "$PKG $VERSION" ;;
  -h|--help|help) echo "$_U" ;;
  *) echo "setup.sh: unknown command '${1:-}'" >&2; echo "$_U" >&2; exit 2 ;;
esac
