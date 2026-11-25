# lssm-tui

Interactive Bash Terminal User Interface (TUI) (`service_manager.sh`) to monitor, manage, and inspect `systemd` services and run user shell scripts on systemd-based Linux distributions.

## Features

- **Systemd Service Management:** Lists enabled and disabled non-template `.service` units alongside user-pinned services, with `start`/`stop`, `restart`, and `enable`/`disable` actions (`stop` and `disable` prompt for confirmation).
- **Pinned Services:** Pin frequently used services to the top of the list in `services.conf`.
- **Service Inspection & Metrics:** View live `CPU %`, `Memory (MB)`, and `PID` (via `ps`), service descriptions (`systemctl show`), `systemctl status`, and the last 30 `journalctl` log lines.
- **User Scripts Runner:** Register, search, and execute `.sh` scripts with `bash` from `scripts.conf`.
- **Live Search & Audit Logging:** Case-insensitive filtering by name, description, or script path, plus structured action logging.
- **Alternate Screen TUI:** Uses the terminal alternate screen buffer, handles terminal resize (`WINCH`), and restores cooked terminal state during prompts, `sudo` calls, modals, and script runs.

## Requirements

- Linux with `systemd` (`systemctl`, `journalctl`)
- `bash`
- Standard utilities: `ps`, `stty`, `tput`, `getent`, `realpath`, `mktemp`, `date`
- `sudo` privileges when running `start`, `stop`, `restart`, `enable`, or `disable` as a non-root user

## Usage

Run directly from a terminal (requires interactive TTY on stdin/stdout):

```bash
./service_manager.sh
```

### CLI Options

```text
Usage: service_manager.sh [OPTIONS]

  --help, -h          Display help text and exit
  --no-log, --nn-log  Disable audit logging
  --config <path>     Override services config path
                      (default: ~/.config/service_manager/services.conf)
  --log <path>        Override audit log path
                      (default: ~/.local/share/service_manager/service_manager.log)
  --scripts <path>    Override scripts config file or directory path
                      (default: <config_dir>/scripts.conf)
```

Examples:

```bash
./service_manager.sh --no-log
./service_manager.sh --config /path/to/services.conf
./service_manager.sh --log /path/to/audit.log --scripts /path/to/scripts.conf
```

## Keybindings

| Key | Action |
| --- | --- |
| `Up` / `Down` | Navigate list rows or move to/from the top action bar |
| `Home` / `End` | Jump to the first or last item in the current list |
| `Left` / `Right` | Select action button (`[start/stop]`, `[restart]`, `[enable/disable]`, or top bar buttons) |
| `Tab` | Toggle focus between the list and top action bar |
| `p` / `P` | Jump to the top system action bar |
| `Enter` | Execute highlighted service/bar action or run selected script |
| `s` / `S` | Toggle between Services view and Scripts view |
| `a` / `A` | Pin selected service (Services view) or add a script (Scripts view) |
| `x` / `X` | Unpin selected service (Services view) or remove selected script (Scripts view) |
| `f` / `F` | Enter search mode (`Enter`/`Tab` confirms, `Esc` clears) |
| `Esc` | Exit search mode, clear active search query, or focus list |
| `d` / `D` | Toggle info bar between service description and `CPU %` / `Memory` / `PID` |
| `j` / `J` | Open `journalctl` modal (last 30 lines, Services view) |
| `i` / `I` | Open `systemctl status` modal (Services view) |
| `r` / `R` | Refresh systemd cache/metrics or reload `scripts.conf` |
| `c` / `C` | Delete config and log files after confirmation |
| `h` / `H` | Open scrollable keybinding cheat sheet |
| `q` / `Q` | Exit `service_manager.sh` |

## Configuration & Logs

When invoked via `sudo`, default paths resolve against `SUDO_USER` (falling back to `USER` or `id -un`, then `HOME`) so configs and logs stay in the invoking user's home directory:

- **Pinned Services (`~/.config/service_manager/services.conf`):** One service unit name per line (blank lines and `#` comments are ignored; `.service` suffixes are stripped):

  ```text
  # Pinned services
  nginx
  docker
  ```

- **User Scripts (`~/.config/service_manager/scripts.conf`):** Stored as `name=path` (also accepts `name:path`; blank lines and `#` comments are ignored):

  ```text
  backup=/home/user/scripts/backup.sh
  cleanup=/home/user/scripts/cleanup.sh
  ```

- **Audit Log (`~/.local/share/service_manager/service_manager.log`):** Records service actions, pinning changes, script config updates, script runs, and config resets:

  ```text
  [2026-01-01 12:00:00] ACTION="restart" TARGET="nginx" RESULT="SUCCESS" DETAILS="Executed restart on nginx"
  ```

## Project Structure

```text
.
├── service_manager.sh          # Entry point and main TUI event loop
└── source.d/
    ├── 00_cli.sh               # CLI flag parsing and --help output
    ├── 01_constants.sh         # ANSI colors, box-drawing constants, default paths
    ├── 02_state.sh             # Global state variables and associative arrays
    ├── 03_terminal.sh          # Alternate screen, cooked-mode wrapper, cleanup trap, audit_log
    ├── 04_data.sh              # Systemd loading, config persistence, filtering, metrics refresh
    ├── 05_ui_helpers.sh        # UTF-8 box frame rendering helpers
    ├── 06_modals.sh            # Confirmation, journalctl/status modals, systemctl execution
    ├── 07_draw.sh              # Main UI layout, lists, cheat sheet, info/hint/status bars
    ├── 08_input.sh             # Raw key reader and WINCH resize handler
    └── 09_scripts.sh           # User script config management and execution
```
