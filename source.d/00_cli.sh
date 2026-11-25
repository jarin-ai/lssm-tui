# shellcheck shell=bash
# ==============================================================================
# COMMAND LINE INTERFACE (CLI OPTIONS)
# ==============================================================================

# Module state (populated by cli__parse)
# shellcheck disable=SC2034
_CLI_NO_LOG=0
# shellcheck disable=SC2034
_CLI_OVERRIDE_CONFIG_FILE=""
# shellcheck disable=SC2034
_CLI_OVERRIDE_LOG_FILE=""
# shellcheck disable=SC2034
_CLI_OVERRIDE_SCRIPTS_CONFIG=""

# Print CLI usage and keybinding help to stdout.
# Inputs: none
# Outputs: help text on stdout
# Returns: 0
cli__show_help() {
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

# Validate that an option requiring a path argument received a non-empty value.
# Inputs: $1=option flag, $2=argument value (may be empty), $3=program name
# Outputs: error message on stderr when invalid
# Returns: 0 if valid, 1 if missing/empty
_cli__require_path_arg() {
    local opt_name="$1"
    local opt_val="$2"
    local prog_name="$3"

    if [[ -z "$opt_val" ]]; then
        printf "Error: %s requires a path argument.\nTry '%s --help' for usage.\n" \
            "$opt_name" "$prog_name" >&2
        return 1
    fi
    return 0
}

# Parse CLI flags and populate _CLI_* state variables.
# Inputs: $1=program name ($0), $@=CLI arguments
# Outputs: help on stdout (--help/-h) or error message on stderr
# Returns: 0 to continue execution, 2 if --help was displayed, 1 on parse error
cli__parse() {
    local prog_name="$1"
    shift

    _CLI_NO_LOG=0
    _CLI_OVERRIDE_CONFIG_FILE=""
    _CLI_OVERRIDE_LOG_FILE=""
    _CLI_OVERRIDE_SCRIPTS_CONFIG=""

    while (( $# > 0 )); do
        case "$1" in
            --help|-h)
                cli__show_help
                return 2
                ;;
            --no-log|--nn-log)
                _CLI_NO_LOG=1
                shift
                ;;
            --config)
                _cli__require_path_arg "--config" "${2:-}" "$prog_name" || return 1
                _CLI_OVERRIDE_CONFIG_FILE="$2"
                shift 2
                ;;
            --log)
                _cli__require_path_arg "--log" "${2:-}" "$prog_name" || return 1
                _CLI_OVERRIDE_LOG_FILE="$2"
                shift 2
                ;;
            --scripts)
                _cli__require_path_arg "--scripts" "${2:-}" "$prog_name" || return 1
                if [[ -d "$2" ]]; then
                    _CLI_OVERRIDE_SCRIPTS_CONFIG="${2%/}/scripts.conf"
                else
                    _CLI_OVERRIDE_SCRIPTS_CONFIG="$2"
                fi
                shift 2
                ;;
            *)
                printf "Error: Unknown option '%s'\nTry '%s --help' for usage.\n" \
                    "$1" "$prog_name" >&2
                return 1
                ;;
        esac
    done

    return 0
}
