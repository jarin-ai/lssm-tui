# ==============================================================================
# USER SCRIPTS BROWSER & RUNNER
# Scripts are stored as .sh files in SCRIPTS_DIR (defined in 00_constants.sh).
# Name  = filename without .sh extension.
# Desc  = first comment line in the file (line starting with #, stripped of #
#         and leading whitespace), or empty string if none found.
# ==============================================================================

load_scripts() {
    SCRIPTS_NAMES=()
    SCRIPTS_DESCS=()

    [[ -d "$SCRIPTS_DIR" ]] || return 0

    local f name desc line
    while IFS= read -r -d '' f; do
        name="${f##*/}"        # basename
        name="${name%.sh}"     # strip extension

        # Read first comment from file
        desc=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*#(.*)$ ]]; then
                desc="${BASH_REMATCH[1]}"
                # strip leading whitespace
                desc="${desc#"${desc%%[! ]*}"}"
                break
            fi
            # Skip shebang on first line; stop on first non-comment/non-shebang
            [[ "$line" =~ ^#! ]] && continue
            break
        done < "$f"

        SCRIPTS_NAMES+=("$name")
        SCRIPTS_DESCS+=("$desc")
    done < <(find "$SCRIPTS_DIR" -maxdepth 1 -name "*.sh" -type f -print0 | sort -z)
}

# ---------------------------------------------------------------------------
# Inner modal body (called inside with_cooked_terminal)
# ---------------------------------------------------------------------------
_scripts_modal_inner() {
    local num_scripts=${#SCRIPTS_NAMES[@]}

    while true; do
        printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"

        print_box_top
        print_box_line "  User Scripts  (${SCRIPTS_DIR})" "$COLOR_TITLE$COLOR_BOLD"
        print_box_divider

        if [[ ! -d "$SCRIPTS_DIR" ]]; then
            print_box_line "  Directory does not exist: ${SCRIPTS_DIR}" "$COLOR_WARN"
            print_box_line "  Create it and place .sh scripts there to get started." "$COLOR_MUTED"
        elif (( num_scripts == 0 )); then
            print_box_line "  No scripts found in: ${SCRIPTS_DIR}" "$COLOR_WARN"
            print_box_line "  Add .sh files to that directory to make them available here." "$COLOR_MUTED"
        else
            # Column header
            local p_hdr_name p_hdr_desc p_hdr_btn
            printf -v p_hdr_name "%-24.24s" "SCRIPT"
            printf -v p_hdr_desc "%-38.38s" "DESCRIPTION"
            printf -v p_hdr_btn  "%-9.9s"   "ACTION"
            print_box_line "  ${p_hdr_name} ${p_hdr_desc} ${p_hdr_btn}" "$COLOR_SECONDARY$COLOR_BOLD"

            local i
            for (( i=0; i<num_scripts; i++ )); do
                local pad_name pad_desc pad_btn
                printf -v pad_name "%-24.24s" "${SCRIPTS_NAMES[$i]}"
                printf -v pad_desc "%-38.38s" "${SCRIPTS_DESCS[$i]}"
                printf -v pad_btn  "%-9.9s"   "[run]"

                local col_name col_btn
                if (( i == SCRIPTS_ROW )); then
                    col_name="${COLOR_BOLD}${COLOR_TEXT}"
                    col_btn="$COLOR_HIGHLIGHT"
                else
                    col_name="$COLOR_TEXT"
                    col_btn="$COLOR_PRIMARY"
                fi

                local row_line="  ${col_name}${pad_name}${COLOR_RESET} ${COLOR_MUTED}${pad_desc}${COLOR_RESET} ${col_btn}${pad_btn}${COLOR_RESET}"
                printf '%s%s%s%s%s%s%s\n' \
                    "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
                    "$row_line" \
                    "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
            done
        fi

        print_box_divider
        if (( num_scripts > 0 )); then
            print_box_line "  [↑/↓] Navigate   [Enter] Run script   [ESC/q] Close" "$COLOR_MUTED"
        else
            print_box_line "  [ESC/q] Close" "$COLOR_MUTED"
        fi
        print_box_bottom

        # Read a key (raw, single char without the read_key helper to avoid
        # sub-shell overhead; we handle the escape sequence ourselves)
        local k=""
        IFS= read -rsn1 k

        if [[ "$k" == $'\x1b' ]]; then
            local seq=""
            IFS= read -rsn1 -t 0.05 seq || true
            if [[ "$seq" == "[" ]]; then
                local code=""
                IFS= read -rsn1 -t 0.05 code || true
                case "$code" in
                    A)  # UP
                        (( SCRIPTS_ROW > 0 )) && (( SCRIPTS_ROW-- ))
                        ;;
                    B)  # DOWN
                        (( SCRIPTS_ROW < num_scripts - 1 )) && (( SCRIPTS_ROW++ ))
                        ;;
                esac
            fi
            # bare ESC or unrecognised sequence → close
            [[ -z "$seq" || "$seq" != "[" ]] && break
            continue
        fi

        case "$k" in
            q|Q)
                break
                ;;
            "" | $'\n' | $'\r')
                # ENTER — run the selected script
                if (( num_scripts > 0 )); then
                    _run_script "${SCRIPTS_NAMES[$SCRIPTS_ROW]}"
                fi
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Execute a script by name and show output in the terminal
# ---------------------------------------------------------------------------
_run_script() {
    local script_name="$1"
    local script_path="${SCRIPTS_DIR}/${script_name}.sh"

    printf '%s%s' "$TERM_CURSOR_HOME" "$TERM_CLEAR_SCREEN"
    print_box_top
    print_box_line "  Running: ${script_name}" "$COLOR_TITLE$COLOR_BOLD"
    print_box_divider

    printf '\n'
    if [[ -f "$script_path" && -x "$script_path" ]]; then
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
    elif [[ ! -f "$script_path" ]]; then
        print_box_line "  Error: Script file not found: ${script_path}" "$COLOR_ERROR$COLOR_BOLD"
        audit_log "SCRIPT_RUN" "$script_name" "FAILURE" "file not found"
    else
        # File exists but not executable — run via bash anyway
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
    fi

    print_box_divider
    print_box_line "  Press [Enter] to return to scripts list..." "$COLOR_HIGHLIGHT$COLOR_BOLD"
    print_box_bottom
    read -r _
}

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------
show_scripts_modal() {
    SCRIPTS_ROW=0
    load_scripts
    with_cooked_terminal _scripts_modal_inner
}
