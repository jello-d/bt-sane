#!/bin/sh
# setup.sh - install / uninstall / check / test the bt-sane Bluetooth UX suite:
# bt-le (the LE/passkey toggle) + bt-indicator (a passive SNI tray icon). The
# SINGLE entry point a consumer or provisioning layer uses.
#
#   ./setup.sh install     copy the payload; link bt-le, bt-mpris (+ man)
#   ./setup.sh service     build the tray-icon venv + enable its --user daemon
#   ./setup.sh all         install + service
#   ./setup.sh uninstall   remove the links, the payload + the --user daemon
#   ./setup.sh check       tools + deps present; [OK]/[FAIL] markers
#   ./setup.sh test        run the in-repo suite (test/run)
#   ./setup.sh version     the packaged version
#
# POSIX sh, non-privileged. `install` is bt-le + man ONLY (the contract a
# provisioner delegates to); the tray icon is a Python/dbus daemon, so it is a
# separate `service` verb (builds a venv, no venv-run dependency). bt-le is a
# ROOT helper in use (it edits /etc/bluetooth/main.conf + restarts bluetooth);
# `install` links it for `bt-le status` by hand, whereas an integrator
# installs it to a root path with a narrow NOPASSWD grant (that privileged
# step is not here).
#
# THE PAYLOAD (the fleet's place-not-link rule, 2026-10-01): an install is a
# COPY at ~/.local/share/bt-sane/{libexec,man,venv}, and ~/.local links only
# into that, never back into the source tree, which a provisioner re-clones
# on every sweep and may wipe at any time.
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
_pay=$_shr/$PKG                      # the payload root
VENV=${BT_SANE_VENV:-$_pay/venv}
OLD_VENV=$HOME/.venvs/bt-sane        # the pre-payload venv, retired
TOOLS="bt-le bt-mpris"               # the commands linked onto PATH
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

# _guard_pay: the payload path is CHECKED before anything near it is removed
# (the standing rm rule), so an empty or odd value never reaches `rm -rf`.
_guard_pay() {
  case $_pay in
  /*/share/"$PKG") ;;
  *) echo "$PKG: refusing to touch a payload at '$_pay'" >&2; return 1 ;;
  esac
}

# _payload_stage: build the new payload beside the live one and swap it in,
# so the links never point at a half-copied tree. The venv is CARRIED
# FORWARD: `install` runs on every provisioning sweep, and a swap that
# dropped the venv would leave the tray launcher pointing at nothing until
# `service` happened to run again. A rename keeps its absolute path, so the
# paths a venv bakes in stay true.
_payload_stage() {
  _guard_pay || return 1
  rm -rf -- "$_pay.new" "$_pay.old"
  mkdir -p "$_pay.new"
  for _d in libexec man; do
    cp -R "$_root/$_d" "$_pay.new/"
  done
  [ -x "$_pay.new/libexec/bt-le" ] || {
    echo "$PKG: staged payload has no libexec/bt-le" >&2
    rm -rf -- "$_pay.new"; return 1; }
  if [ -d "$_pay/venv" ] && [ ! -L "$_pay/venv" ]; then
    mv -- "$_pay/venv" "$_pay.new/venv"
  fi
  if [ -e "$_pay" ] || [ -L "$_pay" ]; then mv -- "$_pay" "$_pay.old"; fi
  mv -- "$_pay.new" "$_pay"
  rm -rf -- "$_pay.old"
}

do_install() {
  mkdir -p "$_bin" "$_shr"
  _payload_stage
  for _t in $TOOLS; do ln -sfn "$_pay/libexec/$_t" "$_bin/$_t"; done
  _man_pages | while IFS= read -r _m; do
    _d=$(basename "$(dirname "$_m")")
    mkdir -p "$_man/$_d"
    ln -sfn "$_pay/man/$_d/${_m##*/}" "$_man/$_d/${_m##*/}"; done
  echo "$PKG: installed to $_pay (+ bin and man links in $PREFIX)"
}

# _retire_old_venv: the pre-payload venv at ~/.venvs/bt-sane, removed only
# AFTER the new one is built, so a failed rebuild never leaves neither. ONLY
# from the real ~/.local install: the old venv path ignores PREFIX, so a
# scratch-prefix run would otherwise delete the live venv out from under the
# running tray (it did, once, while this was being verified).
_retire_old_venv() {
  [ "$_pay" = "$HOME/.local/share/$PKG" ] || return 0
  [ "$VENV" != "$OLD_VENV" ] || return 0
  [ -d "$OLD_VENV" ] || return 0
  case $OLD_VENV in
  "$HOME"/.venvs/?*) rm -rf -- "$OLD_VENV" ;;
  *) echo "$PKG: not retiring '$OLD_VENV': unexpected shape" >&2; return 0 ;;
  esac
  rmdir "$HOME/.venvs" 2>/dev/null || :
  echo "$PKG: retired the old venv at $OLD_VENV"
}

do_service() {
  command -v python3 >/dev/null 2>&1 || {
    echo "$PKG: python3 absent; no tray-icon venv" >&2; return 1; }
  [ -f "$_pay/libexec/bt-indicator" ] || {
    echo "$PKG: no payload at $_pay; run setup.sh install first" >&2
    return 1; }
  [ -d "$VENV" ] || python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q -r "$_root/libexec/bt-indicator.reqs"
  # A launcher: exec the venv python on the packaged daemon (replaces venv-run;
  # this launcher is the only thing the daemon needs on PATH).
  mkdir -p "$_bin"
  cat > "$_bin/bt-indicator" <<EOF
#!/bin/sh
exec "$VENV/bin/python" "$_pay/libexec/bt-indicator" "\$@"
EOF
  chmod +x "$_bin/bt-indicator"
  mkdir -p "$_usr"
  cp "$_root/systemd/bt-indicator.service" "$_usr/bt-indicator.service"
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable bt-indicator.service 2>/dev/null || true
  systemctl --user restart bt-indicator.service 2>/dev/null || true
  _retire_old_venv
  echo "$PKG: bt-indicator venv + --user daemon installed + enabled"
}

do_uninstall() {
  for _t in $TOOLS bt-indicator; do
    if [ -e "$_bin/$_t" ] || [ -L "$_bin/$_t" ]; then rm -f "$_bin/$_t"; fi
  done
  _man_pages | while IFS= read -r _m; do
    _d=$(basename "$(dirname "$_m")")
    _l=$_man/$_d/${_m##*/}
    case $(readlink "$_l" 2>/dev/null) in
    "$_m"|"$_pay/man/$_d/${_m##*/}") rm -f "$_l" ;;
    esac; done
  if [ -e "$_usr/bt-indicator.service" ]; then
    systemctl --user disable --now bt-indicator.service 2>/dev/null || true
    rm -f "$_usr/bt-indicator.service"
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  if [ -d "$_pay" ] && [ ! -L "$_pay" ]; then
    _guard_pay && rm -rf -- "$_pay"
  fi
  echo "$PKG: removed the links, the daemon and $_pay (its venv included)"
  if [ -d "$OLD_VENV" ]; then
    echo "$PKG: KEPT the pre-payload venv $OLD_VENV; delete it by hand"
  fi
}

# _check_payload: the payload is a real tree, and every link this package
# made resolves INTO it. A link resolving into the source tree is the
# pre-payload install, and it dangles the next time that tree is re-cloned.
_check_payload() {
  if [ -L "$_pay" ]; then
    bad "$_pay is a SYMLINK: this install still depends on a source tree"
  elif [ -x "$_pay/libexec/bt-le" ] && [ -d "$_pay/man" ]; then
    ok "payload is a self-contained tree ($_pay)"
  else bad "no payload tree at $_pay (setup.sh install)"; fi
  for _t in $TOOLS; do
    if [ "$(readlink "$_bin/$_t" 2>/dev/null)" = "$_pay/libexec/$_t" ]; then
      ok "$_t linked into the payload"
    elif [ "$(readlink "$_bin/$_t" 2>/dev/null)" = "$_root/libexec/$_t" ]; then
      bad "$_t links into the source tree, not the payload (setup.sh install)"
    else bad "$_t not linked ($_bin/$_t)"; fi
  done
}

do_check() {
  echo "== $PKG (bluetooth tray + LE toggle) =="
  _check_payload
  # The CAPABILITY, reported but never judged. Whether LE or the MPRIS bridge
  # SHOULD be on is the integrator's policy, not this package's: bt-sane exists
  # so both can be turned off deliberately, and a box that wants the bridge is
  # not broken. So state is surfaced for whoever does hold the policy, and only
  # `stale` is called out because masked-but-still-running is nobody's
  # intent, it is just a mask that has not taken effect yet.
  _m=$("$_pay/libexec/bt-mpris" status 2>/dev/null || echo unknown)
  case "$_m" in
    stale) bad "mpris-proxy masked but STILL RUNNING (~1/3 core until the
         session ends; \`bt-mpris off\` stops it now)" ;;
    *)     ok "mpris bridge: $_m" ;;
  esac
  ok "LE: $("$_pay/libexec/bt-le" status 2>/dev/null || echo unknown)"
  for _d in $DEPS; do
    command -v "$_d" >/dev/null 2>&1 && ok "dep $_d present" \
      || warn "dep $_d absent (bluez; the suite needs it)"; done
  for _d in $DEPS_SOFT; do
    command -v "$_d" >/dev/null 2>&1 && ok "dep $_d present" \
      || warn "dep $_d absent (a feature degrades)"; done
  # the tray daemon is opt-in (`service`); audit it only once installed
  if [ -e "$_bin/bt-indicator" ]; then
    [ -x "$VENV/bin/python" ] && ok "tray venv present" \
      || bad "tray launcher present but venv missing (setup.sh service)"
    grep -q "$_pay/libexec/bt-indicator" "$_bin/bt-indicator" \
      && ok "tray launcher runs the payload's daemon" \
      || bad "tray launcher does not run $_pay (setup.sh service)"
    [ -d "$OLD_VENV" ] && [ "$VENV" != "$OLD_VENV" ] \
      && warn "retired venv survives: $OLD_VENV (service removes it)" || :
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
