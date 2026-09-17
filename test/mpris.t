#!/bin/sh
# mpris.t - bt-mpris reports the bridge's state, including the one that hides.
#
# bt-sane exists so the costly parts of Bluetooth can be turned off
# deliberately. mpris-proxy is the expensive one: it busy-loops roughly a third
# of a core in every user manager it starts in, including headless service
# accounts that will never touch a headset.
#
# The state that matters, and the reason status is three-valued, is `stale`:
# MASKING DOES NOT STOP A RUNNING UNIT. A mask governs the next start, so an
# instance already up keeps burning CPU until the session ends, while the mask
# file makes any declaration-only check read clean. Collapsing that into `off`
# is exactly how a busy-loop hides behind a green tick.
#
# Whether the bridge SHOULD be on is not asserted here: that is the integrator's
# policy (tackup masks it fleet-wide), and a box that wants the bridge is not
# broken. This package owns the CAPABILITY -- flipping it, and telling the truth
# about it.
. "$(dirname "$0")/lib.sh"
harness_init mpris

TOOL=$HERE/libexec/bt-mpris
[ -x "$TOOL" ] || fail "libexec/bt-mpris missing or not executable"

MASK=$T/mpris-proxy.service
mkdir -p "$T/bin"
# systemctl --user is-active answers from a marker, so `running` is a fact the
# test controls rather than whatever this developer's session happens to do.
cat > "$T/bin/systemctl" <<EOF
#!/bin/sh
for a in "\$@"; do
  [ "\$a" = is-active ] && {
    [ -f "$T/live" ] && echo active || echo inactive; exit 0; }
done
exit 0
EOF
chmod +x "$T/bin/systemctl"

_st() { env PATH="$T/bin:$PATH" MASK="$MASK" "$TOOL" status; }

# --- not masked: the bridge is available ------------------------------------
rm -f "$MASK" "$T/live"
[ "$(_st)" = on ] || fail "an unmasked bridge should report on, got $(_st)"

# --- masked and stopped: what `off` is supposed to mean ---------------------
ln -sfn /dev/null "$MASK"
[ "$(_st)" = off ] || fail "masked + stopped should report off, got $(_st)"

# --- MASKED BUT STILL RUNNING: the state that hides -------------------------
: > "$T/live"
[ "$(_st)" = stale ] \
  || fail "masked while an instance is LIVE must report stale, not $(_st):
the mask governs the next start, so the busy-loop is still running and a check
that cannot say so reports a hot machine as clean"
rm -f "$T/live"

# --- off/on flip the durable knob -------------------------------------------
# off must also STOP a live instance: the point of the command is that the CPU
# stops now, not at the next logout.
rm -f "$MASK"
env PATH="$T/bin:$PATH" MASK="$MASK" "$TOOL" off || fail "bt-mpris off failed"
[ "$(readlink "$MASK")" = /dev/null ] || fail "off did not mask the unit"
grep -q 'systemctl --user stop' "$TOOL" \
  || fail "off masks but never stops a live instance, so the busy-loop keeps
running until the session ends -- which is the case this tool exists for"
env PATH="$T/bin:$PATH" MASK="$MASK" "$TOOL" on || fail "bt-mpris on failed"
[ -e "$MASK" ] && fail "on did not remove the mask" || :

# --- an unknown verb is an error, not a silent no-op ------------------------
env PATH="$T/bin:$PATH" MASK="$MASK" "$TOOL" bogus >/dev/null 2>&1 \
  && fail "bt-mpris accepted an unknown verb" || :

pass "bt-mpris reports on/off/stale and flips the durable knob"
