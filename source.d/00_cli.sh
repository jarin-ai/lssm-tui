# ==============================================================================
# COMMAND LINE INTERFACE (CLI OPTIONS)
# ==============================================================================
FLAG_NO_LOG=0
# Path overrides — set by --config / --log / --scripts flags before 00_constants.sh
# resolves its readonly values.
_OVERRIDE_CONFIG_FILE=""
_OVERRIDE_LOG_FILE=""
_OVERRIDE_SCRIPTS_DIR=""

show_help() {
    cat << 'EOF'
Usage: service_manager.sh [OPTIONS]

Production-grade interactive Terminal User Interface (TUI) to monitor,
manage, inspect, and log systemd services on Linux Mint and modern Linux.

Options:
  --help                  Display this help documentation and exit immediately.
  --no-log                Disable audit logging. Suppress all write operations to
  --nn-log                ~/.local/share/service_manager/service_manager.log.
  --config <path>         Override default config file path
                          (default: ~/.config/service_manager/services.conf).
  --log <path>            Override default audit log file path
                          (default: ~/.local/share/service_manager/service_manager.log).
  --scripts <dir>         Override default user scripts directory
                          (default: ~/.local/share/service_manager/scripts).

Keybindings & Controls:
  [Up / Down]     Navigate service rows or switch to top System Action Bar
  [Left / Right]  Navigate action buttons across highlighted row ([action1], [restart], [action2])
  [Enter]         Execute highlighted action (prompts [y/N] before stop/disable)
  [t / T]         Toggle between user config list and systemctl list
  [a / A]         Add highlighted service to user config (available in systemctl list)
  [x / X]         Remove highlighted service from user config (available in user list)
  [g / Home]      Jump directly to the top system action bar
  [/]             Enter Search Mode (filters services by name and description)
  [h / H]         Toggle keybinding cheat sheet view
  [c / C]         Clear config and audit logs (prompts confirmation, resets defaults)
  [d / D]         Toggle Information Area view (Description <-> CPU/Memory/PID)
  [l / L]         Open journalctl log viewer modal (last 30 entries)
  [i / I]         Open systemctl status inspection modal
  [r / R]         Manually refresh systemd status cache and process metrics
  [s / S]         Open User Scripts browser
  [ESC]           Exit active search mode, cheat sheet, or clear active search query
  [q / Q]         Cleanly exit service manager

Service Lists:
  User config     Services saved in ~/.config/service_manager/services.conf.
                  Displayed by default when non-empty. Add with [a], remove with [x].
  Systemctl list  All enabled/disabled services reported by systemctl list-unit-files.
                  Displayed when user config is empty or when toggled with [t].

Examples:
  ./service_manager.sh
  ./service_manager.sh --no-log
  ./service_manager.sh --config /path/to/services.conf
  ./service_manager.sh --log /path/to/audit.log --scripts ~/my-scripts
EOF
}

# Parse CLI options prior to UI initialization and pre-flight checks
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --no-log|--nn-log)
            FLAG_NO_LOG=1
            shift
            ;;
        --config)
            if [[ -z "${2:-}" ]]; then
                printf "Error: --config requires a path argument.\nTry '%s --help' for usage.\n" "$0" >&2
                exit 1
            fi
            _OVERRIDE_CONFIG_FILE="$2"
            shift 2
            ;;
        --log)
            if [[ -z "${2:-}" ]]; then
                printf "Error: --log requires a path argument.\nTry '%s --help' for usage.\n" "$0" >&2
                exit 1
            fi
            _OVERRIDE_LOG_FILE="$2"
            shift 2
            ;;
        --scripts)
            if [[ -z "${2:-}" ]]; then
                printf "Error: --scripts requires a directory argument.\nTry '%s --help' for usage.\n" "$0" >&2
                exit 1
            fi
            _OVERRIDE_SCRIPTS_DIR="$2"
            shift 2
            ;;
        *)
            printf "Error: Unknown option '%s'\nTry '%s --help' for usage.\n" "$1" "$0" >&2
            exit 1
            ;;
    esac
done
