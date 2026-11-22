# ==============================================================================
# USER SCRIPTS MANAGER & RUNNER
# Scripts are stored as name=path in SCRIPTS_CONFIG_FILE (defined in 01_constants.sh).
# Located in the same directory as services.conf (e.g. ~/.config/service_manager/scripts.conf).
# ==============================================================================

load_scripts() {
    SCRIPTS_NAMES=()
    SCRIPTS_PATHS=()

    if [[ ! -f "$SCRIPTS_CONFIG_FILE" ]]; then
        filter_scripts
        return 0
    fi

    local line name path
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        if [[ "$line" == *"="* ]]; then
            name="${line%%=*}"
            path="${line#*=}"
        elif [[ "$line" == *":"* ]]; then
            name="${line%%:*}"
            path="${line#*:}"
        else
            continue
        fi

        # Strip surrounding whitespace
        name="${name#"${name%%[![:space:]]*}"}"
        name="${name%"${name##*[![:space:]]}"}"
        path="${path#"${path%%[![:space:]]*}"}"
        path="${path%"${path##*[![:space:]]}"}"

        [[ -z "$name" || -z "$path" ]] && continue

        SCRIPTS_NAMES+=("$name")
        SCRIPTS_PATHS+=("$path")
    done < "$SCRIPTS_CONFIG_FILE"

    filter_scripts
}

filter_scripts() {
    VISIBLE_SCRIPTS=()
    shopt -s nocasematch

    local safe_q pat=""
    if [[ -n "$SEARCH_QUERY" ]]; then
        safe_q=$(escape_glob "$SEARCH_QUERY")
        pat="*${safe_q}*"
    fi

    local i
    for (( i=0; i < ${#SCRIPTS_NAMES[@]}; i++ )); do
        local n="${SCRIPTS_NAMES[$i]}"
        local p="${SCRIPTS_PATHS[$i]}"
        if [[ -n "$pat" ]]; then
            [[ "$n" == $pat || "$p" == $pat ]] || continue
        fi
        VISIBLE_SCRIPTS+=("$i")
    done

    shopt -u nocasematch

    if (( ${#VISIBLE_SCRIPTS[@]} == 0 )); then
        SCRIPTS_ROW=0
    elif (( SCRIPTS_ROW >= ${#VISIBLE_SCRIPTS[@]} )); then
        SCRIPTS_ROW=$(( ${#VISIBLE_SCRIPTS[@]} - 1 ))
    fi
}

save_scripts() {
    local config_dir
    config_dir="$(dirname "$SCRIPTS_CONFIG_FILE")"
    mkdir -p "$config_dir" 2>/dev/null || true
    : > "$SCRIPTS_CONFIG_FILE"
    local i
    for (( i=0; i < ${#SCRIPTS_NAMES[@]}; i++ )); do
        printf '%s=%s\n' "${SCRIPTS_NAMES[$i]}" "${SCRIPTS_PATHS[$i]}" >> "$SCRIPTS_CONFIG_FILE"
    done
}

add_script_to_config() {
    local name="$1"
    local path="$2"

    local i found=0
    for (( i=0; i < ${#SCRIPTS_NAMES[@]}; i++ )); do
        if [[ "${SCRIPTS_NAMES[$i]}" == "$name" ]]; then
            SCRIPTS_PATHS[$i]="$path"
            found=1
            break
        fi
    done

    if (( found == 0 )); then
        SCRIPTS_NAMES+=("$name")
        SCRIPTS_PATHS+=("$path")
    fi

    save_scripts
    filter_scripts

    if (( found == 1 )); then
        CURRENT_STATUS="Status: Updated script '${name}' in config."
        audit_log "UPDATE_SCRIPT_CONFIG" "$name" "SUCCESS" "Updated path to ${path}"
    else
        CURRENT_STATUS="Status: Added script '${name}' to config."
        audit_log "ADD_SCRIPT_CONFIG" "$name" "SUCCESS" "Added with path ${path}"
    fi
}

remove_script_from_config() {
    local target="$1"
    local new_names=()
    local new_paths=()
    local found=0
    local i
    for (( i=0; i < ${#SCRIPTS_NAMES[@]}; i++ )); do
        if [[ "${SCRIPTS_NAMES[$i]}" == "$target" ]]; then
            found=1
        else
            new_names+=("${SCRIPTS_NAMES[$i]}")
            new_paths+=("${SCRIPTS_PATHS[$i]}")
        fi
    done

    if (( found == 0 )); then
        CURRENT_STATUS="Status: Script '${target}' not found in config."
        return 0
    fi

    SCRIPTS_NAMES=("${new_names[@]+"${new_names[@]}"}")
    SCRIPTS_PATHS=("${new_paths[@]+"${new_paths[@]}"}")
    save_scripts
    filter_scripts

    CURRENT_STATUS="Status: Removed script '${target}' from config."
    audit_log "REMOVE_SCRIPT_CONFIG" "$target" "SUCCESS" "Removed from config"
}

_NEW_SCRIPT_NAME=""
_NEW_SCRIPT_PATH=""

_prompt_add_script_modal() {
    _NEW_SCRIPT_NAME=""
    _NEW_SCRIPT_PATH=""

    printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"
    print_box_top
    print_box_line "  ADD USER SCRIPT" "$COLOR_TITLE$COLOR_BOLD"
    print_box_divider
    print_box_line "  Enter script name and path to the .sh file." "$COLOR_TEXT"
    print_box_line "  Config file: ${SCRIPTS_CONFIG_FILE}" "$COLOR_MUTED"
    print_box_line "  Press [Enter] on empty input to cancel." "$COLOR_MUTED"
    print_box_bottom

    printf '\n%s%s%s' "$COLOR_PRIMARY$COLOR_BOLD" "  Script Name: " "$COLOR_RESET"
    local in_name=""
    read -e -r in_name || return 1
    in_name="${in_name#"${in_name%%[![:space:]]*}"}"
    in_name="${in_name%"${in_name##*[![:space:]]}"}"
    if [[ -z "$in_name" ]]; then
        return 1
    fi

    printf '%s%s%s' "$COLOR_PRIMARY$COLOR_BOLD" "  Path to .sh file: " "$COLOR_RESET"
    local in_path=""
    read -e -r in_path || return 1
    in_path="${in_path#"${in_path%%[![:space:]]*}"}"
    in_path="${in_path%"${in_path##*[![:space:]]}"}"
    if [[ -z "$in_path" ]]; then
        return 1
    fi

    in_path="${in_path/#\~/"$HOME"}"
    in_path="$(realpath -m "$in_path" 2>/dev/null || echo "$in_path")"

    _NEW_SCRIPT_NAME="$in_name"
    _NEW_SCRIPT_PATH="$in_path"
    return 0
}

add_script_prompt() {
    if with_cooked_terminal _prompt_add_script_modal; then
        add_script_to_config "$_NEW_SCRIPT_NAME" "$_NEW_SCRIPT_PATH"
    else
        CURRENT_STATUS="Status: Add script cancelled."
    fi
}

_run_script_inner() {
    local script_name="$1"
    local script_path="$2"

    printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"
    print_box_top
    print_box_line "  Running: ${script_name}" "$COLOR_TITLE$COLOR_BOLD"
    print_box_line "  Path: ${script_path}" "$COLOR_MUTED"
    print_box_divider

    printf '\n'
    if [[ -f "$script_path" ]]; then
        bash "$script_path"
        local rc=$?
        printf '\n'
        if (( rc == 0 )); then
            print_box_line "  Script finished (exit 0)." "$COLOR_SUCCESS"
        else
            print_box_line "  Script exited with code ${rc}." "$COLOR_WARN"
        fi
        local _result="FAILURE"
        (( rc == 0 )) && _result="SUCCESS"
        audit_log "SCRIPT_RUN" "$script_name" "$_result" "exit code ${rc}"
    else
        print_box_line "  Error: Script file not found: ${script_path}" "$COLOR_ERROR$COLOR_BOLD"
        audit_log "SCRIPT_RUN" "$script_name" "FAILURE" "file not found"
    fi

    print_box_divider
    print_box_line "  Press [Enter] to return..." "$COLOR_HIGHLIGHT$COLOR_BOLD"
    print_box_bottom
    read -r _
}

_run_script() {
    local script_name="$1"
    local script_path="$2"

    with_cooked_terminal _run_script_inner "$script_name" "$script_path"
}
