# bt-sane

A saner Bluetooth desktop: a **passive** tray indicator that replaces the
CPU-hungry blueman-applet, plus an LE/passkey **toggle**. A suite of tools on
`PATH`; there is no eponymous `bt-sane` command.

## Tools

- **bt-indicator** — a passive StatusNotifierItem tray icon. It reads BlueZ once
  on the system bus and subscribes to `PropertiesChanged` only on the adapter +
  paired devices (never the LE advertisement flood), so it sits at ~0% idle.
  Left-click connects/disconnects, middle-click toggles LE (via `bt-le`),
  right-click opens `blueman-manager`. Runs as a `--user` systemd daemon.
- **bt-le** — `bt-le on|off|status` flips the BlueZ `ControllerMode` between
  `dual` (LE on) and `bredr` (classic only), restarting bluetoothd. `status` is
  world-readable; `on`/`off` edit `/etc/bluetooth/main.conf` and need root.

## Why

BlueZ defaults to `dual` mode; in an RF-dense room LE discovery floods
blueman-applet with hundreds of transient beacons and it busy-spins a CPU.
`bredr` costs nothing when all your gear is classic audio, and `bt-le` flips
back for a session that needs LE. The tray icon is passive by construction.

## Install

    ./setup.sh install      # link bt-le (+ man) into ~/.local
    ./setup.sh service      # build the tray venv + enable its --user daemon
    ./setup.sh all          # install + service
    ./setup.sh check        # tools + deps present; [OK]/[FAIL] markers
    ./setup.sh test         # the in-repo suite (also: sh test/run)

Honors `PREFIX` (default `~/.local`) and the `XDG_*` vars. `install` links
`bt-le` for `bt-le status` by hand; the tray daemon (`bt-indicator`, a
Python/dbus daemon) is the opt-in `service` verb — it builds its own venv
(`dbus-next` + `Pillow`), no `venv-run` dependency. Runtime deps: `bluez`
(bluetoothd),
`blueman` (the right-click manager, soft), `python3` (for the tray).

## Integration seams

- **`bt-le` is a root helper in use.** `install` links it for hand use, but its
  `on`/`off` need root. A provisioning layer installs it to a root path (e.g.
  `/usr/local/sbin/bt-le`) with a narrow NOPASSWD grant, and the tray's
  middle-click reaches it via `sudo -n`.
- **`BT_LE`** — the path the tray invokes (default `/usr/local/sbin/bt-le`).
- **`BT_CONF`** — the BlueZ main.conf path (default `/etc/bluetooth/main.conf`).

A capability-gated "disable the older of two Bluetooth adapters" step is a
separate integrator concern (it keys on a hardware-capability profile), not part
of this suite.

## License

Apache-2.0.
