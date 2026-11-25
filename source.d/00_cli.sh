# ==============================================================================
# COMMAND LINE INTERFACE (CLI OPTIONS)
# ==============================================================================
FLAG_NO_LOG=0
# Path overrides — set by --config / --log / --scripts flags before 01_constants.sh
# resolves its readonly values.
_OVERRIDE_CONFIG_FILE=""
_OVERRIDE_LOG_FILE=""
_OVERRIDE_SCRIPTS_CONFIG=""

show_help() {
    cat << 'EOF'
Usage: service_manager.sh [OPTIONS]

Interactive Terminal User Interface (TUI) to monitor, manage, inspect, and log
systemd services and manage, and run user scripts on modern Linux.

Options:
  --help                  Display this help documentation and exit immediately.
  --no-log                Disable audit logging. Suppress all write operations to
  --nn-log                ~/.local/share/service_manager/service_manager.log.
  --config <path>         Override default config file path
                          (default: ~/.config/service_manager/services.conf).
  --log <path>            Override default audit log file path
                          (default: ~/.local/share/service_manager/service_manager.log).
  --scripts <path>        Override default scripts config file path
                          (default: ~/.config/service_manager/scripts.conf).

Keybindings & Controls:
  [Up / Down]     Navigate rows or switch to top System Action Bar
  [Home / End]    Jump to the first / last item in the current list
  [Left / Right]  Navigate action buttons across highlighted row
  [Tab]           Toggle focus between the list and top System Action Bar
  [p / P]         Jump directly to the top System Action Bar
  [Enter]         Execute highlighted action (service action or run script)
  [s / S]         Toggle between Services view and User Scripts view
  [a / A]         Add: add script to config (scripts) / pin service (services)
  [x / X]         Remove: remove script (scripts) / unpin service (services)
  [f / F]         Enter Search Mode (filters items by name and path/description)
  [ESC]           Exit active search mode, clear filter, or focus list
  [d / D]         Toggle Information Area view (Description <-> CPU/Memory/PID)
  [j / J]         Open journalctl log viewer modal (services view)
  [i / I]         Open systemctl status inspection modal (services view)
  [r / R]         Manually refresh status cache / reload scripts
  [c / C]         Clear config and audit logs (prompts confirmation, resets defaults)
  [h / H]         Toggle keybinding cheat sheet view
  [q / Q]         Cleanly exit service manager

Service & Script Lists:
  Services        Systemd services monitored and managed via systemctl.
  User scripts    Scripts saved in ~/.config/service_manager/scripts.conf.
                  Add with [a], remove with [x], run with [Enter].

Examples:
  ./service_manager.sh
  ./service_manager.sh --no-log
  ./service_manager.sh --config /path/to/services.conf
  ./service_manager.sh --log /path/to/audit.log --scripts /path/to/scripts.conf
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
                printf "Error: --scripts requires a path argument.\nTry '%s --help' for usage.\n" "$0" >&2
                exit 1
            fi
            if [[ -d "$2" ]]; then
                _OVERRIDE_SCRIPTS_CONFIG="${2%/}/scripts.conf"
            else
                _OVERRIDE_SCRIPTS_CONFIG="$2"
            fi
            shift 2
            ;;
        *)
            printf "Error: Unknown option '%s'\nTry '%s --help' for usage.\n" "$1" "$0" >&2
            exit 1
            ;;
    esac
done
