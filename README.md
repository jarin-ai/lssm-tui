# lssm-tui

[![Release](https://img.shields.io/github/v/release/jarin-ai/lssm-tui?label=release)](https://github.com/jarin-ai/lssm-tui/releases/tag/v0.1.0)
![Platform](https://img.shields.io/badge/platform-Linux-FCC624?logo=linux&logoColor=white)
![Bash](https://img.shields.io/badge/bash-4.3%2B-4EAA25?logo=gnubash&logoColor=white)
![systemd](https://img.shields.io/badge/systemd-systemctl%20%7C%20journalctl-2F74C0)

Interactive Bash Terminal User Interface (TUI) (`service_manager.sh`) for monitoring, managing, and inspecting `systemd` services alongside custom user shell scripts on `systemd`-based Linux distributions.

## Features

- **Systemd Service Management:** Lists `enabled` and `disabled` non-template `.service` units together with user-pinned services. Supports `start`/`stop`, `restart`, and `enable`/`disable` actions via `systemctl` (or `sudo systemctl` when not running as root), with `[y/N]` confirmation prompts for `stop` and `disable`.
- **Pinned Services:** Pin frequently used services to the top of the list in `services.conf` (sorted alphabetically and separated visually from the remaining system units).
- **Live Resource Metrics & Inspection:** Toggle the info bar between service descriptions (`systemctl show`) and live process metrics (`CPU %`, `Memory (MB)`, and `MainPID` via `ps`), or open full modals for `systemctl status` and the last 30 `journalctl` log lines.
- **User Scripts Runner:** Register, search, and execute `.sh` scripts with `bash` from `scripts.conf`, with real-time terminal output and exit-code reporting.
- **Live Search & Audit Logging:** Case-insensitive filtering across service names/descriptions or script names/paths, plus timestamped audit logging for service actions, config edits, and script runs.
- **Flicker-Free Alternate Screen TUI:** Renders inside the terminal alternate screen buffer, adapts to terminal resizes (`SIGWINCH`), buffers stderr across TUI exit, and cleanly restores cooked terminal settings during prompts, `sudo` authentication, modals, and script execution.

## Example TUI Screens

### Services View (with Pinned Services & Live Resource Metrics)

```text
╭────────────────────────────────────────────────────────────────────────────╮
│                          Linux systemctl manager                           │
├────────────────────────────────────────────────────────────────────────────┤
│  Actions:  [services]  [scripts]  [search]  [clear]  [help]                │
├────────────────────────────────────────────────────────────────────────────┤
│  SERVICE          STATE        ACTION 1  RESTART     STARTUP     ACTION 2  │
│  nginx            active       [stop]    [restart]   enabled     [disable] │
│  docker           active       [stop]    [restart]   enabled     [disable] │
│            ── pinned ──────────────────────────── systemctl ──             │
│  cron             active       [stop]    [restart]   enabled     [disable] │
│  postgresql       inactive     [start]   [restart]   disabled    [enable]  │
│  ssh              active       [stop]    [restart]   enabled     [disable] │
│  ufw              active       [stop]    [restart]   enabled     [disable] │
├────────────────────────────────────────────────────────────────────────────┤
│  Resource Usage: CPU: 0.4% | Memory: 18.2 MB | PID: 1428                   │
├────────────────────────────────────────────────────────────────────────────┤
│  Hint: [x] unpin service. [j] logs. [i] status. [d] info. [r] refresh.     │
├────────────────────────────────────────────────────────────────────────────┤
│  Status: Ready.                                                            │
╰────────────────────────────────────────────────────────────────────────────╯
```

### User Scripts View

```text
╭────────────────────────────────────────────────────────────────────────────╮
│                          Linux systemctl manager                           │
├────────────────────────────────────────────────────────────────────────────┤
│  Actions:  [services]  [scripts]  [search]  [clear]  [help]                │
├────────────────────────────────────────────────────────────────────────────┤
│  SCRIPT                 PATH                                     ACTION    │
│  backup                 /home/user/scripts/backup.sh             [run]     │
│  cleanup                /home/user/scripts/cleanup.sh            [run]     │
│  healthcheck            /opt/tools/healthcheck.sh                [run]     │
│                                                                            │
│                                                                            │
├────────────────────────────────────────────────────────────────────────────┤
│  Script: backup | Path: /home/user/scripts/backup.sh                       │
├────────────────────────────────────────────────────────────────────────────┤
│  Hint: Press [Enter] to run 'backup'. [a] add script, [x] remove script. [ │
├────────────────────────────────────────────────────────────────────────────┤
│  Status: Scripts view active.                                              │
╰────────────────────────────────────────────────────────────────────────────╯
```

### Keybinding Cheat Sheet (`h`)

```text
╭────────────────────────────────────────────────────────────────────────────╮
│                          Linux systemctl manager                           │
├────────────────────────────────────────────────────────────────────────────┤
│  Actions:  [services]  [scripts]  [search]  [clear]  [help]                │
├────────────────────────────────────────────────────────────────────────────┤
│  KEYBINDING       ACTION / DESCRIPTION                                     │
│  [↑ / ↓]       Navigate rows or switch to system action bar                │
│  [Home / End]  Jump to first / last item in the current list               │
│  [← / →]       Navigate action buttons across highlighted row              │
│  [Tab]         Toggle focus between list and system action bar             │
│  [p / P]       Jump directly to top system action bar                      │
│  [Enter]       Execute highlighted action (service action or script)       │
├────────────────────────────────────────────────────────────────────────────┤
│  Information: Keybinding Cheat Sheet (Lines 1-6 of 18)                     │
├────────────────────────────────────────────────────────────────────────────┤
│  Hint: Press [Enter] to view keybinding cheat sheet (or press 'h').        │
├────────────────────────────────────────────────────────────────────────────┤
│  Status: Ready.                                                            │
╰────────────────────────────────────────────────────────────────────────────╯
```

## Requirements

- Linux with `systemd` (`systemctl`, `journalctl`)
- `bash` 4.3+ (uses associative arrays, namerefs, lowercase expansion, and `printf` time formatting)
- Standard utilities: `ps`, `stty`, `tput`, `getent`, `realpath`, `mktemp`, `id`
- `sudo` privileges when executing `start`, `stop`, `restart`, `enable`, or `disable` as a non-root user
- An interactive terminal (TTY on both stdin and stdout)

## How to Install

`service_manager.sh` sources its modules from the `source.d/` directory next to it, so keep `service_manager.sh` and `source.d/` together in the same directory.

### Option 1: Clone the repository

```bash
git clone https://github.com/jarin-ai/lssm-tui.git
cd lssm-tui
chmod +x service_manager.sh
./service_manager.sh
```

### Option 2: Download and unpack a release archive

```bash
curl -LO https://github.com/jarin-ai/lssm-tui/releases/download/v0.1.0/lssm-tui-v0.1.0.tar.gz
tar -xzf lssm-tui-v0.1.0.tar.gz
```

Change into the extracted directory, ensure the entrypoint is executable if needed (`chmod +x service_manager.sh`), and run `./service_manager.sh`.

## Usage

Run directly from an interactive terminal:

```bash
./service_manager.sh
```

### CLI Options

| Option | Description |
| --- | --- |
| `--help`, `-h` | Display help text and exit |
| `--no-log`, `--nn-log` | Disable audit logging |
| `--config <path>` | Override services config path (default: `~/.config/service_manager/services.conf`) |
| `--log <path>` | Override audit log path (default: `~/.local/share/service_manager/service_manager.log`) |
| `--scripts <path>` | Override scripts config file or directory path (default: `<config_dir>/scripts.conf`) |

> Note: When `--scripts` points to an existing directory, `scripts.conf` inside that directory is used automatically. When `--scripts` is omitted, it defaults to `scripts.conf` in the directory of `--config` (or `~/.config/service_manager/`).

Examples:

```bash
./service_manager.sh --no-log
./service_manager.sh --config /path/to/services.conf
./service_manager.sh --log /path/to/audit.log --scripts /path/to/scripts.conf
```

## Keybindings

| Key | Action |
| --- | --- |
| `Up` / `Down` | Navigate list rows, scroll the cheat sheet, or move between the list and top action bar |
| `Home` / `End` | Jump to the first or last item in the current list |
| `Left` / `Right` | Select action button (`[start/stop]`, `[restart]`, `[enable/disable]`, or top bar buttons) |
| `Tab` | Toggle focus between the list and top action bar |
| `p` / `P` | Jump directly to the top system action bar |
| `Enter` | Execute highlighted service/bar action or run selected script |
| `s` / `S` | Toggle between Services view and User Scripts view |
| `a` / `A` | Pin selected service (Services view) or open prompt to add/update a script (Scripts view) |
| `x` / `X` | Unpin selected service (Services view) or remove selected script from config (Scripts view) |
| `f` / `F` | Enter Search Mode (`Backspace` edits, `Enter`/`Tab` applies and focuses results, `Esc` clears) |
| `Esc` | Exit search mode, clear active search query, or return focus to the list |
| `d` / `D` | Toggle Information Area between service `Description` and `CPU %` / `Memory` / `PID` |
| `j` / `J` | Open `journalctl` modal (last 30 lines, Services view) |
| `i` / `I` | Open `systemctl status` modal (Services view) |
| `r` / `R` | Refresh `systemd` cache and process metrics, or reload `scripts.conf` |
| `c` / `C` | Delete config and log files after confirmation and reset to defaults |
| `h` / `H` | Open scrollable keybinding cheat sheet |
| `q` / `Q` | Exit `service_manager.sh` |

## Configuration & Audit Logs

When invoked via `sudo`, default paths resolve against `SUDO_USER` (falling back to `USER`, `id -un`, and then `HOME`) so configuration and log files remain in the invoking user's home directory.

- **Pinned Services (`~/.config/service_manager/services.conf`):** One service unit name per line (blank lines and `#` comments are ignored; `.service` suffixes are stripped):

  ```text
  # Pinned services
  nginx
  docker
  ```

- **User Scripts (`~/.config/service_manager/scripts.conf`):** Stored as `name=path` (also accepts `name:path`; blank lines and `#` comments are ignored). Adding scripts via `a` supports `~` expansion and resolves paths with `realpath -m`:

  ```text
  backup=/home/user/scripts/backup.sh
  cleanup=/home/user/scripts/cleanup.sh
  ```

- **Audit Log (`~/.local/share/service_manager/service_manager.log`):** Records `start`/`stop`/`restart`/`enable`/`disable` actions, service pinning changes, script config updates, script executions, and config resets:

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
    ├── 02_state.sh             # Global state variables and pure-Bash utilities
    ├── 03_terminal.sh          # Alternate screen, cooked-mode wrapper, cleanup trap, audit_log
    ├── 04_data.sh              # Systemd loading, config persistence, filtering, metrics refresh
    ├── 05_ui_helpers.sh        # UTF-8 box frame rendering helpers
    ├── 06_modals.sh            # Confirmation, journalctl/status modals, systemctl execution
    ├── 07_draw.sh              # Main UI layout, lists, cheat sheet, info/hint/status bars
    ├── 08_input.sh             # Raw key reader and SIGWINCH resize handler
    └── 09_scripts.sh           # User script config management and execution
```
