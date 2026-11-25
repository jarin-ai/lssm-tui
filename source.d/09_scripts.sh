# shellcheck shell=bash
# ==============================================================================
# USER SCRIPTS MANAGER & RUNNER
# Scripts are stored as name=path in SCRIPTS_CONFIG_FILE.
# ==============================================================================

# Load script entries from SCRIPTS_CONFIG_FILE and apply current search filter.
# Inputs: none (reads SCRIPTS_CONFIG_FILE)
# Outputs: populates STATE_SCRIPTS_NAMES, STATE_SCRIPTS_PATHS, STATE_VISIBLE_SCRIPTS
# Returns: 0
scripts__load() {
    STATE_SCRIPTS_NAMES=()
    STATE_SCRIPTS_PATHS=()

    if [[ ! -f "$SCRIPTS_CONFIG_FILE" ]]; then
        scripts__filter
        return 0
    fi

    local line="" name="" path=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        util__trim line
        [[ -z "$line" || "$line" == \#* ]] && continue

        if [[ "$line" == *"="* ]]; then
            name="${line%%=*}"
            path="${line#*=}"
        elif [[ "$line" == *":"* ]]; then
            name="${line%%:*}"
            path="${line#*:}"
        else
            continue
        fi

        util__trim name
        util__trim path
        [[ -z "$name" || -z "$path" ]] && continue

        STATE_SCRIPTS_NAMES+=("$name")
        STATE_SCRIPTS_PATHS+=("$path")
    done < "$SCRIPTS_CONFIG_FILE"

    scripts__filter
}

# Filter STATE_SCRIPTS_NAMES/PATHS by STATE_SEARCH_QUERY into STATE_VISIBLE_SCRIPTS.
# Inputs: none (reads STATE_SEARCH_QUERY, STATE_SCRIPTS_NAMES, STATE_SCRIPTS_PATHS)
# Outputs: updates STATE_VISIBLE_SCRIPTS and clamps STATE_SCRIPTS_ROW
# Returns: 0
scripts__filter() {
    STATE_VISIBLE_SCRIPTS=()
    local query_lower="${STATE_SEARCH_QUERY,,}"
    local i=0 n="" p="" total=${#STATE_SCRIPTS_NAMES[@]}

    for (( i=0; i < total; i++ )); do
        n="${STATE_SCRIPTS_NAMES[i]}"
        p="${STATE_SCRIPTS_PATHS[i]}"
        if [[ -n "$query_lower" ]]; then
            [[ "${n,,}" == *"$query_lower"* || "${p,,}" == *"$query_lower"* ]] || continue
        fi
        STATE_VISIBLE_SCRIPTS+=("$i")
    done

    local visible_count=${#STATE_VISIBLE_SCRIPTS[@]}
    if (( visible_count == 0 )); then
        STATE_SCRIPTS_ROW=0
    elif (( STATE_SCRIPTS_ROW >= visible_count )); then
        STATE_SCRIPTS_ROW=$(( visible_count - 1 ))
    fi
}

# Persist STATE_SCRIPTS_NAMES and STATE_SCRIPTS_PATHS to SCRIPTS_CONFIG_FILE.
# Inputs: none
# Outputs: writes SCRIPTS_CONFIG_FILE
# Returns: 0
_scripts__save() {
    local config_dir=""
    util__dirname "$SCRIPTS_CONFIG_FILE" config_dir
    mkdir -p "$config_dir" 2>/dev/null || true

    local i=0 total=${#STATE_SCRIPTS_NAMES[@]}
    {
        for (( i=0; i < total; i++ )); do
            printf '%s=%s\n' "${STATE_SCRIPTS_NAMES[i]}" "${STATE_SCRIPTS_PATHS[i]}"
        done
    } > "$SCRIPTS_CONFIG_FILE"
}

# Add or update a user script entry in config.
# Inputs: $1=script name, $2=script path
# Outputs: updates script arrays, SCRIPTS_CONFIG_FILE, status, audit log
# Returns: 0
scripts__add_to_config() {
    local name="$1"
    local path="$2"

    local i=0 found=0 total=${#STATE_SCRIPTS_NAMES[@]}
    for (( i=0; i < total; i++ )); do
        if [[ "${STATE_SCRIPTS_NAMES[i]}" == "$name" ]]; then
            STATE_SCRIPTS_PATHS[i]="$path"
            found=1
            break
        fi
    done

    if (( found == 0 )); then
        STATE_SCRIPTS_NAMES+=("$name")
        STATE_SCRIPTS_PATHS+=("$path")
    fi

    _scripts__save
    scripts__filter

    if (( found == 1 )); then
        state__set_status "Status: Updated script '${name}' in config."
        audit__log "UPDATE_SCRIPT_CONFIG" "$name" "SUCCESS" "Updated path to ${path}"
    else
        state__set_status "Status: Added script '${name}' to config."
        audit__log "ADD_SCRIPT_CONFIG" "$name" "SUCCESS" "Added with path ${path}"
    fi
}

# Remove a user script entry by name from config.
# Inputs: $1=script name
# Outputs: updates script arrays, SCRIPTS_CONFIG_FILE, status, audit log
# Returns: 0
scripts__remove_from_config() {
    local target="$1"
    local -a new_names=()
    local -a new_paths=()
    local i=0 found=0 total=${#STATE_SCRIPTS_NAMES[@]}

    for (( i=0; i < total; i++ )); do
        if [[ "${STATE_SCRIPTS_NAMES[i]}" == "$target" ]]; then
            found=1
        else
            new_names+=("${STATE_SCRIPTS_NAMES[i]}")
            new_paths+=("${STATE_SCRIPTS_PATHS[i]}")
        fi
    done

    if (( found == 0 )); then
        state__set_status "Status: Script '${target}' not found in config."
        return 0
    fi

    STATE_SCRIPTS_NAMES=("${new_names[@]+"${new_names[@]}"}")
    STATE_SCRIPTS_PATHS=("${new_paths[@]+"${new_paths[@]}"}")
    _scripts__save
    scripts__filter

    state__set_status "Status: Removed script '${target}' from config."
    audit__log "REMOVE_SCRIPT_CONFIG" "$target" "SUCCESS" "Removed from config"
}

_scripts__prompt_add_modal() {
    local -n _spam_name="$1"
    local -n _spam_path="$2"

    _spam_name=""
    _spam_path=""

    printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"
    ui__print_box_top
    ui__print_box_line "  ADD USER SCRIPT" "$COLOR_TITLE$COLOR_BOLD"
    ui__print_box_divider
    ui__print_box_line "  Enter script name and path to the .sh file." "$COLOR_TEXT"
    ui__print_box_line "  Config file: ${SCRIPTS_CONFIG_FILE}" "$COLOR_MUTED"
    ui__print_box_line "  Press [Enter] on empty input to cancel." "$COLOR_MUTED"
    ui__print_box_bottom

    printf '\n%s%s%s' "$COLOR_PRIMARY$COLOR_BOLD" "  Script Name: " "$COLOR_RESET"
    local _spam_in_name=""
    read -e -r _spam_in_name || return 1
    util__trim _spam_in_name
    if [[ -z "$_spam_in_name" ]]; then
        return 1
    fi

    printf '%s%s%s' "$COLOR_PRIMARY$COLOR_BOLD" "  Path to .sh file: " "$COLOR_RESET"
    local _spam_in_path=""
    read -e -r _spam_in_path || return 1
    util__trim _spam_in_path
    if [[ -z "$_spam_in_path" ]]; then
        return 1
    fi

    _spam_in_path="${_spam_in_path/#\~/"$REAL_HOME"}"
    local _spam_resolved=""
    if _spam_resolved=$(realpath -m "$_spam_in_path" 2>/dev/null); then
        _spam_in_path="$_spam_resolved"
    fi

    _spam_name="$_spam_in_name"
    _spam_path="$_spam_in_path"
    return 0
}

# Prompt user to add a new script via cooked-terminal modal.
# Inputs: none
# Outputs: adds script on confirmation or sets cancelled status
# Returns: 0
scripts__add_prompt() {
    local new_name=""
    local new_path=""

    if term__with_cooked_terminal _scripts__prompt_add_modal new_name new_path; then
        scripts__add_to_config "$new_name" "$new_path"
    else
        state__set_status "Status: Add script cancelled."
    fi
}

_scripts__run_inner() {
    local script_name="$1"
    local script_path="$2"

    printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"
    ui__print_box_top
    ui__print_box_line "  Running: ${script_name}" "$COLOR_TITLE$COLOR_BOLD"
    ui__print_box_line "  Path: ${script_path}" "$COLOR_MUTED"
    ui__print_box_divider

    printf '\n'
    if [[ -f "$script_path" ]]; then
        local rc=0
        bash "$script_path" || rc=$?
        printf '\n'
        if (( rc == 0 )); then
            ui__print_box_line "  Script finished (exit 0)." "$COLOR_SUCCESS"
        else
            ui__print_box_line "  Script exited with code ${rc}." "$COLOR_WARN"
        fi
        local result="FAILURE"
        if (( rc == 0 )); then
            result="SUCCESS"
        fi
        audit__log "SCRIPT_RUN" "$script_name" "$result" "exit code ${rc}"
    else
        ui__print_box_line "  Error: Script file not found: ${script_path}" "$COLOR_ERROR$COLOR_BOLD"
        audit__log "SCRIPT_RUN" "$script_name" "FAILURE" "file not found"
    fi

    ui__wait_modal_footer "  Press [Enter] to return..."
}

# Execute a registered user script inside a cooked terminal modal.
# Inputs: $1=script name, $2=script path
# Outputs: script execution UI on stdout and audit log entry
# Returns: 0
scripts__run() {
    local script_name="$1"
    local script_path="$2"
    term__with_cooked_terminal _scripts__run_inner "$script_name" "$script_path"
}
