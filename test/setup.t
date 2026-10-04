#!/bin/sh
# setup.t - the install roundtrip against a scratch PREFIX: install -> assert
# the payload is a COPY and every link resolves into it, never into the repo
# -> a reinstall keeps the venv -> check -> uninstall -> assert gone. Nothing
# outside the scratch dir. The `service` verb is NOT exercised: it builds a
# real venv and reaches the live --user manager (systemctl --user enable),
# neither of which belongs in a stub test (the vigilance/hush precedent).
. "$(dirname "$0")/harness_lib"
harness_init setup

PREFIX=$T/local
XDG_BIN_HOME=$PREFIX/bin
XDG_DATA_HOME=$PREFIX/share
# CONFIG AND HOME TOO: `uninstall` disables and deletes the --user unit under
# $XDG_CONFIG_HOME, so without these the roundtrip stopped and removed the
# LIVE tray daemon on whatever box ran the suite.
XDG_CONFIG_HOME=$T/config
HOME=$T/home
export PREFIX XDG_BIN_HOME XDG_DATA_HOME XDG_CONFIG_HOME HOME

PAY=$XDG_DATA_HOME/bt-sane
sh "$HERE/setup.sh" install >/dev/null || fail "install errored"
[ -d "$PAY" ] && [ ! -L "$PAY" ] || fail "payload is not a real directory"
[ -L "$PAY/bin/bt-le" ] && fail "payload holds a link, not a copy" || :
for _t in bt-le bt-mpris; do
  [ "$(readlink "$XDG_BIN_HOME/$_t")" = "$PAY/bin/$_t" ] \
    || fail "$_t link does not point into the payload"
done
[ "$(readlink -f "$XDG_DATA_HOME/man/man1/bt-sane.1")" \
  = "$(readlink -f "$PAY/man/man1/bt-sane.1")" ] \
  || fail "man page does not resolve into the payload"
# THE PLACEMENT RULE ITSELF: nothing installed resolves into the source tree.
_src=$(readlink -f "$HERE")
# (collected, then judged: a `fail` inside the pipeline's subshell is lost)
_into=$(find "$PREFIX" -type l | while IFS= read -r _l; do
  case $(readlink -f "$_l") in "$_src"/*) printf '%s ' "$_l" ;; esac
done)
[ -z "$_into" ] || fail "resolves into the source tree: $_into"

# a reinstall (every provisioning sweep) must CARRY the venv forward
mkdir -p "$PAY/venv" && : >"$PAY/venv/marker"
sh "$HERE/setup.sh" install >/dev/null || fail "reinstall errored"
[ -f "$PAY/venv/marker" ] || fail "reinstall dropped the venv"
[ -e "$PAY.new" ] || [ -e "$PAY.old" ] && fail "staging dirs left behind" || :

# check reports bt-le linked (deps may be absent in the sandbox; do not gate on
# RC, only that it reports the tool). Put the sandbox bin first on PATH.
PATH="$XDG_BIN_HOME:$PATH" sh "$HERE/setup.sh" check >"$T/check.out" 2>&1 \
  || true
grep -q '\[OK\].*bt-le linked into the payload' "$T/check.out" \
  || fail "check did not report bt-le"
# with no tray launcher installed, check WARNs (does not fail) about the daemon
grep -q '\[WARN\].*tray icon not installed' "$T/check.out" \
  || fail "check did not note the opt-in tray daemon"

sh "$HERE/setup.sh" uninstall >/dev/null || fail "uninstall errored"
[ -e "$XDG_BIN_HOME/bt-le" ] && fail "bt-le still present after uninstall" || :
[ -e "$XDG_DATA_HOME/man/man1/bt-sane.1" ] && fail "man not removed" || :
[ -e "$PAY" ] && fail "payload still present after uninstall" || :

pass "install/check/uninstall roundtrip"
