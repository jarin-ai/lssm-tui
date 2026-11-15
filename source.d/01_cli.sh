# ==============================================================================
# COMMAND LINE INTERFACE (CLI OPTIONS)
# ==============================================================================
FLAG_NO_CONFIG=0
FLAG_NO_LOG=0

show_help() {
    cat << 'EOF'
Usage: service_manager.sh [OPTIONS]

Production-grade interactive Terminal User Interface (TUI) to monitor,
manage, inspect, and log systemd services on Linux Mint and modern Linux.

Options:
  --help          Display this help documentation and exit immediately.
  --no-config     Ignore ~/.config/service_manager/services.conf even if it exists.
                  Load all available services directly from systemctl instead.
  --no-log        Disable audit logging. Suppress all write operations to
  --nn-log        ~/.local/share/service_manager/service_manager.log.

Keybindings & Controls:
  [Up / Down]     Navigate service rows or switch to top System Action Bar
  [Left / Right]  Navigate action buttons across highlighted row ([action1], [restart], [action2])
  [Enter]         Execute highlighted action (prompts [y/N] before stop/disable)
  [/]             Enter Search Mode (filters services by name and description)
  [h / H]         Toggle keybinding cheat sheet view
  [c / C]         Clear config and audit logs (prompts confirmation, resets defaults)
  [d / D]         Toggle Information Area view (Description <-> CPU/Memory/PID)
  [l / L]         Open journalctl log viewer modal (last 30 entries)
  [i / I]         Open systemctl status inspection modal
  [r / R]         Manually refresh systemd status cache and process metrics
  [ESC]           Exit active search mode, cheat sheet, or clear active search query
  [q / Q]         Cleanly exit service manager

Examples:
  ./service_manager.sh
  ./service_manager.sh --no-config
  ./service_manager.sh --no-log
  ./service_manager.sh --no-config --no-log
EOF
}

# Parse CLI options prior to UI initialization and pre-flight checks
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --no-config)
            FLAG_NO_CONFIG=1
            shift
            ;;
        --no-log|--nn-log)
            FLAG_NO_LOG=1
            shift
            ;;
        *)
            printf "Error: Unknown option '%s'\nTry '%s --help' for usage.\n" "$1" "$0" >&2
            exit 1
            ;;
    esac
done
