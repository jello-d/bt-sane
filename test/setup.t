#!/bin/sh
# setup.t - the install roundtrip against a scratch PREFIX: install -> assert
# bt-le + man land -> check -> uninstall -> assert gone. Nothing outside the
# scratch dir. The `service` verb is NOT exercised: it builds a real venv and
# reaches the live --user manager (systemctl --user enable), neither of which
# belongs in a stub test (the vigilance/hush precedent).
. "$(dirname "$0")/lib.sh"
harness_init setup

PREFIX=$T/local
XDG_BIN_HOME=$PREFIX/bin
XDG_DATA_HOME=$PREFIX/share
export PREFIX XDG_BIN_HOME XDG_DATA_HOME

sh "$HERE/setup.sh" install >/dev/null || fail "install errored"
[ -L "$XDG_BIN_HOME/bt-le" ] || fail "bt-le not linked"
[ "$(readlink "$XDG_BIN_HOME/bt-le")" = "$HERE/libexec/bt-le" ] \
  || fail "bt-le link does not point at the repo"
[ -e "$XDG_DATA_HOME/man/man1/bt-sane.1" ] || fail "man page not installed"

# check reports bt-le linked (deps may be absent in the sandbox; do not gate on
# RC, only that it reports the tool). Put the sandbox bin first on PATH.
PATH="$XDG_BIN_HOME:$PATH" sh "$HERE/setup.sh" check >"$T/check.out" 2>&1 \
  || true
grep -q '\[OK\].*bt-le linked' "$T/check.out" \
  || fail "check did not report bt-le"
# with no tray launcher installed, check WARNs (does not fail) about the daemon
grep -q '\[WARN\].*tray icon not installed' "$T/check.out" \
  || fail "check did not note the opt-in tray daemon"

sh "$HERE/setup.sh" uninstall >/dev/null || fail "uninstall errored"
[ -e "$XDG_BIN_HOME/bt-le" ] && fail "bt-le still present after uninstall" || :
[ -e "$XDG_DATA_HOME/man/man1/bt-sane.1" ] && fail "man not removed" || :

pass "install/check/uninstall roundtrip"
