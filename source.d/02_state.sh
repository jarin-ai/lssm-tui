# ==============================================================================
# STATE MANAGEMENT & DATA STRUCTURES
# ==============================================================================
VISIBLE_SERVICES=()
SYSCTRL_SERVICES=()   # Always loaded from systemctl list-unit-files
USER_SERVICES=()       # Loaded from config file (pinned services)
PINNED_COUNT=0         # Number of pinned (user) services currently visible

declare -A SVC_ACTIVE_STATE
declare -A SVC_UNIT_STATE
declare -A SVC_DESCRIPTION
declare -A SVC_PID
declare -A CPU_USAGE
declare -A MEM_USAGE

SCRIPTS_NAMES=()           # Basenames (no .sh) of discovered scripts
SCRIPTS_DESCS=()           # First-comment descriptions, parallel to SCRIPTS_NAMES
SCRIPTS_ROW=0              # Selected row in scripts modal

FOCUS_AREA="services"      # "services" or "system"
SYS_BTN=0                 # 0: [services], 1: [scripts], 2: [search], 3: [clear], 4: [help]
SELECTED_ROW=0            # Index within VISIBLE_SERVICES
SELECTED_BTN=0            # 0: [action1], 1: [restart], 2: [action2]
SCROLL_OFFSET=0           # Viewport scrolling offset
INFO_MODE=0               # 0: Description, 1: Live CPU/Memory
HELP_MODE=0               # 0: Normal service list, 1: Keybinding cheat sheet
SEARCH_MODE=0             # 0: Idle, 1: Active query typing
SEARCH_QUERY=""           # Current search string
CURRENT_STATUS="Status: Ready." # Execution result status message
SAVED_TTY_SETTINGS=""     # Cooked terminal mode backup
TERM_LINES=24             # Detected terminal rows
TERM_COLS=80              # Detected terminal columns
