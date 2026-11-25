# shellcheck shell=bash
# ==============================================================================
# TUI SCREEN LAYOUT STRUCTURE RENDERING
# ==============================================================================

readonly DRAW_CHEAT_LINES=(
    "  [↑ / ↓]       Navigate rows or switch to system action bar"
    "  [Home / End]  Jump to first / last item in the current list"
    "  [← / →]       Navigate action buttons across highlighted row"
    "  [Tab]         Toggle focus between list and system action bar"
    "  [p / P]       Jump directly to top system action bar"
    "  [Enter]       Execute highlighted action (service action or script)"
    "  [s / S]       Toggle between Services view and User Scripts view"
    "  [a / A]       Add script to config (scripts) / pin service (services)"
    "  [x / X]       Remove script (scripts) / unpin service (services)"
    "  [f / F]       Enter Search Mode (filter by name or description/path)"
    "  [ESC]         Exit active search / clear filter / focus list"
    "  [d / D]       Toggle Information Area (Description <-> CPU/Memory/PID)"
    "  [j / J]       Open journalctl log viewer modal (services view)"
    "  [i / I]       Open systemctl status inspection modal (services view)"
    "  [r / R]       Manually refresh status cache / reload scripts"
    "  [c / C]       Clear config and audit logs (prompts confirmation)"
    "  [h / H]       Open keybinding cheat sheet view"
    "  [q / Q]       Cleanly exit service manager"
)

# Return the number of cheat sheet lines via nameref.
# Inputs: $1=nameref to output integer
# Outputs: sets referenced variable
# Returns: 0
draw__get_cheat_count() {
    local -n _dgcc_out="$1"
    _dgcc_out=${#DRAW_CHEAT_LINES[@]}
}

# Populate the context-sensitive hint string via nameref (no subshell).
# Inputs: $1=nameref to output string
# Outputs: sets referenced variable
# Returns: 0
draw__get_hint_text() {
    local -n _dght_out="$1"

    if (( STATE_SEARCH_MODE == 1 )); then
        _dght_out="Type query. Press [Enter] to finish search, [ESC] to cancel filter."
        return 0
    fi

    if [[ "$STATE_FOCUS_AREA" == "system" ]] || (( STATE_HELP_MODE == 1 )); then
        case "$STATE_SYS_BTN" in
            0) _dght_out="Press [Enter] to switch to services view." ;;
            1) _dght_out="Press [Enter] to switch to user scripts view (or press 's')." ;;
            2) _dght_out="Press [Enter] to enter Search Mode (or press 'f')." ;;
            3) _dght_out="Press [Enter] to clear config & logs (or press 'c')." ;;
            4) _dght_out="Press [Enter] to view keybinding cheat sheet (or press 'h')." ;;
            *) _dght_out="" ;;
        esac
        return 0
    fi

    if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
        if (( ${#STATE_VISIBLE_SCRIPTS[@]} == 0 )); then
            _dght_out="Press [a] to add a new script. [p] jump to action bar."
            return 0
        fi
        local _dght_idx="${STATE_VISIBLE_SCRIPTS[$STATE_SCRIPTS_ROW]}"
        local _dght_scr="${STATE_SCRIPTS_NAMES[$_dght_idx]}"
        _dght_out="Press [Enter] to run '${_dght_scr}'. [a] add script, [x] remove script. [p] bar."
        return 0
    fi

    if (( ${#STATE_VISIBLE_SERVICES[@]} == 0 )); then
        _dght_out="No matching services. Press [ESC] to clear search filter."
        return 0
    fi

    local _dght_svc="${STATE_VISIBLE_SERVICES[$STATE_SELECTED_ROW]}"
    if data__is_pinned "$_dght_svc"; then
        _dght_out="[x] unpin service. [j] logs. [i] status. [d] info. [r] refresh."
    else
        _dght_out="[a] pin service. [j] logs. [i] status. [d] info. [r] refresh."
    fi
}

_draw__help() {
    local available_rows="$1"

    local p_hdr_key="" p_hdr_action=""
    printf -v p_hdr_key    "%-16.16s" "KEYBINDING"
    printf -v p_hdr_action "%-56.56s" "ACTION / DESCRIPTION"

    local hdr_content="  ${p_hdr_key} ${p_hdr_action} "
    ui__print_box_line "$hdr_content" "$COLOR_SECONDARY$COLOR_BOLD"

    local total_lines=${#DRAW_CHEAT_LINES[@]}
    local max_scroll=$(( total_lines - available_rows ))
    if (( max_scroll < 0 )); then
        max_scroll=0
    fi

    if (( STATE_HELP_SCROLL_OFFSET < 0 )); then
        STATE_HELP_SCROLL_OFFSET=0
    elif (( STATE_HELP_SCROLL_OFFSET > max_scroll )); then
        STATE_HELP_SCROLL_OFFSET=$max_scroll
    fi

    local rendered=0
    local idx=$STATE_HELP_SCROLL_OFFSET

    while (( rendered < available_rows )); do
        if (( idx >= total_lines )); then
            ui__print_box_line "" "$COLOR_TEXT"
        else
            ui__print_box_line "${DRAW_CHEAT_LINES[$idx]}" "$COLOR_SECONDARY"
            idx=$(( idx + 1 ))
        fi
        rendered=$(( rendered + 1 ))
    done
}

# Draw inline separator row between pinned and system sections.
_draw__pin_separator() {
    local label=" ── pinned ──────────────────────────── systemctl ── "
    local llen=${#label}
    local left_pad=$(( (INNER_WIDTH - llen) / 2 ))
    local right_pad=$(( INNER_WIDTH - llen - left_pad ))
    local lp="" rp=""
    printf -v lp "%*s" "$left_pad" ""
    printf -v rp "%*s" "$right_pad" ""
    local sep_line="${lp}${label}${rp}"
    printf '%s%s%s%s%s%s%s\n' \
        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
        "${COLOR_MUTED}${sep_line}${COLOR_RESET}" \
        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
}

_draw__services_list() {
    local available_rows="$1"

    local p_hdr_name="" p_hdr_active="" p_hdr_btn1="" p_hdr_btn2="" p_hdr_unit="" p_hdr_btn3=""
    printf -v p_hdr_name   "%-16.16s" "SERVICE"
    printf -v p_hdr_active "%-12.12s" "STATE"
    printf -v p_hdr_btn1   "%-9.9s"   "ACTION 1"
    printf -v p_hdr_btn2   "%-11.11s" "RESTART"
    printf -v p_hdr_unit   "%-11.11s" "STARTUP"
    printf -v p_hdr_btn3   "%-9.9s"   "ACTION 2"

    local hdr_content="  ${p_hdr_name} ${p_hdr_active} ${p_hdr_btn1} ${p_hdr_btn2} ${p_hdr_unit} ${p_hdr_btn3} "
    ui__print_box_line "$hdr_content" "$COLOR_SECONDARY$COLOR_BOLD"

    local total_visible=${#STATE_VISIBLE_SERVICES[@]}
    local has_separator=0
    if (( STATE_PINNED_COUNT > 0 && total_visible > STATE_PINNED_COUNT )); then
        has_separator=1
    fi

    if (( total_visible == 0 )); then
        STATE_SCROLL_OFFSET=0
        ui__print_box_line "  (No services match search filter)" "$COLOR_MUTED"
        local r=1
        for (( r=1; r < available_rows; r++ )); do
            ui__print_box_line "" "$COLOR_TEXT"
        done
        return 0
    fi

    local selected_vrow=$STATE_SELECTED_ROW
    if (( has_separator == 1 && STATE_SELECTED_ROW >= STATE_PINNED_COUNT )); then
        selected_vrow=$(( selected_vrow + 1 ))
    fi

    local total_vrows=$(( total_visible + has_separator ))
    local max_scroll=$(( total_vrows - available_rows ))
    if (( max_scroll < 0 )); then
        max_scroll=0
    fi

    if (( selected_vrow < STATE_SCROLL_OFFSET )); then
        STATE_SCROLL_OFFSET=$selected_vrow
    elif (( selected_vrow >= STATE_SCROLL_OFFSET + available_rows )); then
        STATE_SCROLL_OFFSET=$(( selected_vrow - available_rows + 1 ))
    fi
    if (( STATE_SCROLL_OFFSET > max_scroll )); then
        STATE_SCROLL_OFFSET=$max_scroll
    elif (( STATE_SCROLL_OFFSET < 0 )); then
        STATE_SCROLL_OFFSET=0
    fi

    local rendered=0
    local vrow=0 service_idx=0 svc="" a_state="" u_state=""
    local btn1_label="" btn2_label="[restart]" btn3_label=""
    local pad_svc="" pad_act="" pad_b1="" pad_b2="" pad_unt="" pad_b3=""
    local col_svc="" is_row_active=0 col_act="" col_unt=""
    local col_b1="" col_b2="" col_b3="" row_colored=""

    while (( rendered < available_rows )); do
        vrow=$(( STATE_SCROLL_OFFSET + rendered ))
        if (( vrow >= total_vrows )); then
            ui__print_box_line "" "$COLOR_TEXT"
            rendered=$(( rendered + 1 ))
            continue
        fi

        if (( has_separator == 1 && vrow == STATE_PINNED_COUNT )); then
            _draw__pin_separator
            rendered=$(( rendered + 1 ))
            continue
        fi

        service_idx=$vrow
        if (( has_separator == 1 && vrow > STATE_PINNED_COUNT )); then
            service_idx=$(( service_idx - 1 ))
        fi

        svc="${STATE_VISIBLE_SERVICES[$service_idx]}"
        a_state="${STATE_SVC_ACTIVE[$svc]:-unknown}"
        u_state="${STATE_SVC_UNIT[$svc]:-unknown}"

        btn1_label="[start]"
        if [[ "$a_state" == "active" ]]; then
            btn1_label="[stop]"
        fi
        btn3_label="[enable]"
        if [[ "$u_state" == "enabled" ]]; then
            btn3_label="[disable]"
        fi

        # ANSI Padding Rule: ALWAYS pad plain text with printf BEFORE applying colors
        printf -v pad_svc "%-16.16s" "$svc"
        printf -v pad_act "%-12.12s" "$a_state"
        printf -v pad_b1  "%-9.9s"   "$btn1_label"
        printf -v pad_b2  "%-11.11s" "$btn2_label"
        printf -v pad_unt "%-11.11s" "$u_state"
        printf -v pad_b3  "%-9.9s"   "$btn3_label"

        col_svc="$COLOR_TEXT"
        is_row_active=0
        if [[ "$STATE_FOCUS_AREA" == "services" ]] && (( service_idx == STATE_SELECTED_ROW )); then
            is_row_active=1
            col_svc="${COLOR_BOLD}${COLOR_TEXT}"
        fi

        if data__is_pinned "$svc"; then
            if (( is_row_active == 1 )); then
                col_svc="${COLOR_BOLD}${COLOR_ACCENT}"
            else
                col_svc="${COLOR_ACCENT}"
            fi
        fi

        col_act="$COLOR_MUTED"
        case "$a_state" in
            active)
                col_act="$COLOR_SUCCESS"
                ;;
            failed)
                col_act="${COLOR_ERROR}${COLOR_BOLD}"
                ;;
            activating|reloading|deactivating)
                col_act="$COLOR_WARN"
                ;;
        esac

        col_unt="$COLOR_MUTED"
        case "$u_state" in
            enabled)
                col_unt="$COLOR_SUCCESS"
                ;;
            masked)
                col_unt="$COLOR_ERROR"
                ;;
            static|indirect)
                col_unt="$COLOR_WARN"
                ;;
        esac

        col_b1="$COLOR_PRIMARY"
        col_b2="$COLOR_PRIMARY"
        col_b3="$COLOR_PRIMARY"

        if (( is_row_active == 1 )); then
            case "$STATE_SELECTED_BTN" in
                0) col_b1="$COLOR_HIGHLIGHT" ;;
                1) col_b2="$COLOR_HIGHLIGHT" ;;
                2) col_b3="$COLOR_HIGHLIGHT" ;;
            esac
        fi

        row_colored="  ${col_svc}${pad_svc}${COLOR_RESET} ${col_act}${pad_act}${COLOR_RESET} ${col_b1}${pad_b1}${COLOR_RESET} ${col_b2}${pad_b2}${COLOR_RESET} ${col_unt}${pad_unt}${COLOR_RESET} ${col_b3}${pad_b3}${COLOR_RESET} "
        printf '%s%s%s%s%s%s%s\n' \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
            "$row_colored" \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"

        rendered=$(( rendered + 1 ))
    done
}

_draw__scripts_list() {
    local available_rows="$1"

    local p_hdr_name="" p_hdr_path="" p_hdr_btn=""
    printf -v p_hdr_name "%-22.22s" "SCRIPT"
    printf -v p_hdr_path "%-40.40s" "PATH"
    printf -v p_hdr_btn  "%-9.9s"   "ACTION"

    local hdr_content="  ${p_hdr_name} ${p_hdr_path} ${p_hdr_btn} "
    ui__print_box_line "$hdr_content" "$COLOR_SECONDARY$COLOR_BOLD"

    local total_visible=${#STATE_VISIBLE_SCRIPTS[@]}
    if (( total_visible == 0 )); then
        ui__print_box_line "  No scripts to be displayed." "$COLOR_MUTED"
        local r=1
        for (( r=1; r < available_rows; r++ )); do
            ui__print_box_line "" "$COLOR_TEXT"
        done
        return 0
    fi

    if (( STATE_SCRIPTS_ROW < STATE_SCRIPTS_SCROLL_OFFSET )); then
        STATE_SCRIPTS_SCROLL_OFFSET=$STATE_SCRIPTS_ROW
    elif (( STATE_SCRIPTS_ROW >= STATE_SCRIPTS_SCROLL_OFFSET + available_rows )); then
        STATE_SCRIPTS_SCROLL_OFFSET=$(( STATE_SCRIPTS_ROW - available_rows + 1 ))
    fi

    local rendered=0
    local script_idx=$STATE_SCRIPTS_SCROLL_OFFSET
    local actual_idx=0 s_name="" s_path="" s_btn="[run]"
    local pad_name="" pad_path="" pad_btn=""
    local col_name="" col_path="" col_btn="" row_colored=""

    while (( rendered < available_rows )); do
        if (( script_idx >= total_visible )); then
            ui__print_box_line "" "$COLOR_TEXT"
            rendered=$(( rendered + 1 ))
            continue
        fi

        actual_idx="${STATE_VISIBLE_SCRIPTS[$script_idx]}"
        s_name="${STATE_SCRIPTS_NAMES[$actual_idx]}"
        s_path="${STATE_SCRIPTS_PATHS[$actual_idx]}"

        printf -v pad_name "%-22.22s" "$s_name"
        printf -v pad_path "%-40.40s" "$s_path"
        printf -v pad_btn  "%-9.9s"   "$s_btn"

        col_name="$COLOR_TEXT"
        col_path="$COLOR_MUTED"
        col_btn="$COLOR_PRIMARY"

        if [[ "$STATE_FOCUS_AREA" == "services" ]] && (( script_idx == STATE_SCRIPTS_ROW )); then
            col_name="${COLOR_BOLD}${COLOR_TEXT}"
            col_path="${COLOR_TEXT}"
            col_btn="$COLOR_HIGHLIGHT"
        fi

        row_colored="  ${col_name}${pad_name}${COLOR_RESET} ${col_path}${pad_path}${COLOR_RESET} ${col_btn}${pad_btn}${COLOR_RESET} "
        printf '%s%s%s%s%s%s%s\n' \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
            "$row_colored" \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"

        script_idx=$(( script_idx + 1 ))
        rendered=$(( rendered + 1 ))
    done
}

# Render the full TUI screen frame to stdout.
# Inputs: none (reads STATE_* globals)
# Outputs: formatted TUI frame on stdout
# Returns: 0
draw__ui() {
    # Move to Home without clearing to eliminate screen flicker
    printf '%s' "$TERM_CURSOR_HOME"

    # 1. Application Title Banner
    ui__print_box_top
    local title_str="Linux systemctl manager"
    local left_pad=$(( (INNER_WIDTH - ${#title_str}) / 2 ))
    local right_pad=$(( INNER_WIDTH - ${#title_str} - left_pad ))
    local p_title=""
    printf -v p_title "%*s%s%*s" "$left_pad" "" "$title_str" "$right_pad" ""
    ui__print_box_line "$p_title" "$COLOR_TITLE$COLOR_BOLD"

    ui__print_box_divider

    # 2. System Action Bar
    if (( STATE_SEARCH_MODE == 1 )); then
        local search_prefix="  Search: "
        local cursor_sym="_"
        local max_query_len=$(( INNER_WIDTH - ${#search_prefix} - ${#cursor_sym} ))
        local shown_query="$STATE_SEARCH_QUERY"
        if (( ${#shown_query} > max_query_len )); then
            shown_query="${shown_query: -$max_query_len}"
        fi
        local used_len=$(( ${#search_prefix} + ${#shown_query} + ${#cursor_sym} ))
        local fill_len=$(( INNER_WIDTH - used_len ))
        if (( fill_len < 0 )); then
            fill_len=0
        fi
        local pad_fill=""
        if (( fill_len > 0 )); then
            printf -v pad_fill "%*s" "$fill_len" ""
        fi
        local search_line="  ${COLOR_ACCENT}Search: ${COLOR_RESET}${COLOR_BOLD}${COLOR_TEXT}${shown_query}${COLOR_PRIMARY}_${COLOR_RESET}${pad_fill}"
        printf '%s%s%s%s%s%s%s\n' \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
            "$search_line" \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
    else
        local btn_services_style="$COLOR_ACCENT"
        local btn_scripts_style="$COLOR_ACCENT"
        local btn_search_style="$COLOR_ACCENT"
        local btn_clear_style="$COLOR_ACCENT"
        local btn_help_style="$COLOR_ACCENT"

        if [[ "$STATE_FOCUS_AREA" == "system" ]] || (( STATE_HELP_MODE == 1 )); then
            btn_services_style="$COLOR_PRIMARY"
            btn_scripts_style="$COLOR_PRIMARY"
            btn_search_style="$COLOR_PRIMARY"
            btn_clear_style="$COLOR_PRIMARY"
            btn_help_style="$COLOR_PRIMARY"
            case "$STATE_SYS_BTN" in
                0) btn_services_style="$COLOR_HIGHLIGHT" ;;
                1) btn_scripts_style="$COLOR_HIGHLIGHT" ;;
                2) btn_search_style="$COLOR_HIGHLIGHT" ;;
                3) btn_clear_style="$COLOR_HIGHLIGHT" ;;
                4) btn_help_style="$COLOR_HIGHLIGHT" ;;
            esac
        else
            if [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
                btn_scripts_style="${COLOR_BOLD}${COLOR_TEXT}"
            else
                btn_services_style="${COLOR_BOLD}${COLOR_TEXT}"
            fi
        fi

        local plain_text="  Actions:  [services]  [scripts]  [search]  [clear]  [help]"
        local pad_sys_len=$(( INNER_WIDTH - ${#plain_text} ))
        local pad_sys=""
        printf -v pad_sys "%*s" "$pad_sys_len" ""
        local sys_line="  Actions:  ${btn_services_style}[services]${COLOR_RESET}  ${btn_scripts_style}[scripts]${COLOR_RESET}  ${btn_search_style}[search]${COLOR_RESET}  ${btn_clear_style}[clear]${COLOR_RESET}  ${btn_help_style}[help]${COLOR_RESET}${pad_sys}"

        printf '%s%s%s%s%s%s%s\n' \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
            "$sys_line" \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
    fi

    ui__print_box_divider

    # 3. Main List Area
    local available_rows=0
    util__clamp_list_rows "$STATE_TERM_LINES" available_rows

    if (( STATE_HELP_MODE == 1 )); then
        _draw__help "$available_rows"
    elif [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
        _draw__scripts_list "$available_rows"
    else
        _draw__services_list "$available_rows"
    fi

    ui__print_box_divider

    # 4. Information Area
    local info_text=""
    if (( STATE_HELP_MODE == 1 )); then
        local cur_from=$(( STATE_HELP_SCROLL_OFFSET + 1 ))
        local cur_to=$(( STATE_HELP_SCROLL_OFFSET + available_rows ))
        if (( cur_to > ${#DRAW_CHEAT_LINES[@]} )); then
            cur_to=${#DRAW_CHEAT_LINES[@]}
        fi
        info_text="  Information: Keybinding Cheat Sheet (Lines ${cur_from}-${cur_to} of ${#DRAW_CHEAT_LINES[@]})"
    elif [[ "$STATE_CURRENT_VIEW" == "scripts" ]]; then
        if (( ${#STATE_VISIBLE_SCRIPTS[@]} > 0 )); then
            local actual_idx="${STATE_VISIBLE_SCRIPTS[$STATE_SCRIPTS_ROW]}"
            local s_name="${STATE_SCRIPTS_NAMES[$actual_idx]}"
            local s_path="${STATE_SCRIPTS_PATHS[$actual_idx]}"
            info_text="  Script: ${s_name} | Path: ${s_path}"
        else
            info_text="  Information: No script selected (press [a] to add script)"
        fi
    else
        if (( ${#STATE_VISIBLE_SERVICES[@]} > 0 )); then
            local cur_svc="${STATE_VISIBLE_SERVICES[$STATE_SELECTED_ROW]}"
            if (( STATE_INFO_MODE == 0 )); then
                info_text="  Description: ${STATE_SVC_DESC[$cur_svc]:-No description available}"
            else
                local cpu_val="${STATE_CPU_USAGE[$cur_svc]:-0.0}"
                local mem_val="${STATE_MEM_USAGE[$cur_svc]:-0.0}"
                local pid_val="${STATE_SVC_PID[$cur_svc]:-0}"
                if [[ "$pid_val" == "0" ]]; then
                    pid_val="None"
                fi
                info_text="  Resource Usage: CPU: ${cpu_val}% | Memory: ${mem_val} MB | PID: ${pid_val}"
            fi
        else
            info_text="  Information: No service selected"
        fi
    fi
    ui__print_box_line "$info_text" "$COLOR_ACCENT"

    ui__print_box_divider

    # 5. Hint Area
    local hint_body=""
    draw__get_hint_text hint_body
    ui__print_box_line "  Hint: ${hint_body}" "$COLOR_MUTED"

    ui__print_box_divider

    # 6. Status Bar
    local col_status="$COLOR_PRIMARY"
    if [[ "$STATE_CURRENT_STATUS" == *Success* || "$STATE_CURRENT_STATUS" == *Added* || "$STATE_CURRENT_STATUS" == *Pinned* ]]; then
        col_status="$COLOR_SUCCESS"
    elif [[ "$STATE_CURRENT_STATUS" == *Error* || "$STATE_CURRENT_STATUS" == *Failed* ]]; then
        col_status="${COLOR_ERROR}${COLOR_BOLD}"
    fi
    ui__print_box_line "  ${STATE_CURRENT_STATUS}" "$col_status"

    ui__print_box_bottom
}
