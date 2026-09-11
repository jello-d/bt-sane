#!/bin/sh
# tools.t - every shipped script PARSES under its own shell (dash for POSIX sh,
# python for the daemon, bash for bash scripts), dispatched by shebang. Data
# files (*.reqs) are skipped. A parse error ships a broken command.
. "$(dirname "$0")/lib.sh"
harness_init tools

_checker() {   # <file> -> the -n syntax check for its shebang
  case "$(head -1 "$1")" in
    *bash) bash -n "$1" ;;
    *python*) python3 -m py_compile "$1" ;;
    *) dash -n "$1" 2>/dev/null || sh -n "$1" ;;
  esac
}

_n=0
for _f in "$HERE"/setup.sh "$HERE"/test/run "$HERE"/libexec/*; do
  [ -f "$_f" ] || continue
  case "$_f" in *.reqs) continue ;; esac   # data, not a script
  _checker "$_f" || fail "parse error in $(basename "$_f")"
  _n=$((_n + 1))
done

pass "$_n scripts parse"
