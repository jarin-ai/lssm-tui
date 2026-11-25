# ==============================================================================
# TUI SCREEN LAYOUT STRUCTURE RENDERING
# ==============================================================================

get_hint_text() {
    if (( SEARCH_MODE == 1 )); then
        echo "Type query. Press [Enter] to finish search, [ESC] to cancel filter."
        return
    fi
    if [[ "$FOCUS_AREA" == "system" ]] || (( HELP_MODE == 1 )); then
        case "$SYS_BTN" in
            0) echo "Press [Enter] to switch to services view." ;;
            1) echo "Press [Enter] to switch to user scripts view (or press 's')." ;;
            2) echo "Press [Enter] to enter Search Mode (or press 'f')." ;;
            3) echo "Press [Enter] to clear config & logs (or press 'c')." ;;
            4) echo "Press [Enter] to view keybinding cheat sheet (or press 'h')." ;;
        esac
        return
    fi

    if [[ "$CURRENT_VIEW" == "scripts" ]]; then
        if (( ${#VISIBLE_SCRIPTS[@]} == 0 )); then
            echo "Press [a] to add a new script. [p] jump to action bar."
            return
        fi
        local actual_idx="${VISIBLE_SCRIPTS[$SCRIPTS_ROW]}"
        local current_scr="${SCRIPTS_NAMES[$actual_idx]}"
        echo "Press [Enter] to run '${current_scr}'. [a] add script, [x] remove script. [p] bar."
        return
    fi

    if (( ${#VISIBLE_SERVICES[@]} == 0 )); then
        echo "No matching services. Press [ESC] to clear search filter."
        return
    fi

    local current_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
    if _is_pinned "$current_svc"; then
        echo "[x] unpin service. [j] logs. [i] status. [d] info. [r] refresh."
    else
        echo "[a] pin service. [j] logs. [i] status. [d] info. [r] refresh."
    fi
}

readonly CHEAT_LINES=(
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

_draw_help() {
    local available_rows="$1"

    # Header Row
    local p_hdr_key p_hdr_action
    printf -v p_hdr_key    "%-16.16s" "KEYBINDING"
    printf -v p_hdr_action "%-56.56s" "ACTION / DESCRIPTION"

    local hdr_content="  ${p_hdr_key} ${p_hdr_action} "
    print_box_line "$hdr_content" "$COLOR_SECONDARY$COLOR_BOLD"

    local total_lines=${#CHEAT_LINES[@]}
    local max_scroll=$(( total_lines - available_rows ))
    (( max_scroll < 0 )) && max_scroll=0

    if (( HELP_SCROLL_OFFSET < 0 )); then
        HELP_SCROLL_OFFSET=0
    elif (( HELP_SCROLL_OFFSET > max_scroll )); then
        HELP_SCROLL_OFFSET=$max_scroll
    fi

    local rendered=0
    local idx=$HELP_SCROLL_OFFSET

    while (( rendered < available_rows )); do
        if (( idx >= total_lines )); then
            print_box_line "" "$COLOR_TEXT"
        else
            print_box_line "${CHEAT_LINES[$idx]}" "$COLOR_SECONDARY"
            (( idx++ ))
        fi
        (( rendered++ ))
    done
}

render_cheat_sheet() {
    local available_rows=$(( TERM_LINES - 15 ))
    (( available_rows < 5 ))  && available_rows=5
    (( available_rows > 15 )) && available_rows=15
    _draw_help "$available_rows"
}

# Draw an inline separator row between pinned and system sections.
# Shows a dim horizontal rule with a centred label.
_draw_pin_separator() {
    local label=" ── pinned ──────────────────────────── systemctl ── "
    local llen=${#label}
    local left_pad=$(( (INNER_WIDTH - llen) / 2 ))
    local right_pad=$(( INNER_WIDTH - llen - left_pad ))
    local lp rp
    printf -v lp "%*s" "$left_pad" ""
    printf -v rp "%*s" "$right_pad" ""
    local sep_line="${lp}${label}${rp}"
    printf '%s%s%s%s%s%s%s\n' \
        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
        "${COLOR_MUTED}${sep_line}${COLOR_RESET}" \
        "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
}

_draw_services_list() {
    local available_rows="$1"

    # Column Header Row
    local p_hdr_name p_hdr_active p_hdr_btn1 p_hdr_btn2 p_hdr_unit p_hdr_btn3
    printf -v p_hdr_name   "%-16.16s" "SERVICE"
    printf -v p_hdr_active "%-12.12s" "STATE"
    printf -v p_hdr_btn1   "%-9.9s"   "ACTION 1"
    printf -v p_hdr_btn2   "%-11.11s" "RESTART"
    printf -v p_hdr_unit   "%-11.11s" "STARTUP"
    printf -v p_hdr_btn3   "%-9.9s"   "ACTION 2"

    local hdr_content="  ${p_hdr_name} ${p_hdr_active} ${p_hdr_btn1} ${p_hdr_btn2} ${p_hdr_unit} ${p_hdr_btn3} "
    print_box_line "$hdr_content" "$COLOR_SECONDARY$COLOR_BOLD"

    # Calculate visible rows and scroll window.
    # Reserve 1 extra row for the separator between pinned and system sections
    # (only when both sections have matching entries).
    local has_separator=0
    if (( PINNED_COUNT > 0 && ${#VISIBLE_SERVICES[@]} > PINNED_COUNT )); then
        has_separator=1
    fi

    # Scroll logic operates on virtual rows: each real service row maps 1-to-1,
    # but the separator is an extra rendered line inserted between sections.
    if (( SELECTED_ROW < SCROLL_OFFSET )); then
        SCROLL_OFFSET=$SELECTED_ROW
    elif (( SELECTED_ROW >= SCROLL_OFFSET + available_rows )); then
        SCROLL_OFFSET=$(( SELECTED_ROW - available_rows + 1 ))
    fi

    local total_visible=${#VISIBLE_SERVICES[@]}
    if (( total_visible == 0 )); then
        print_box_line "  (No services match search filter)" "$COLOR_MUTED"
        for (( r=1; r < available_rows; r++ )); do
            print_box_line "" "$COLOR_TEXT"
        done
    else
        # Render up to available_rows visual lines, accounting for the separator.
        local rendered=0        # visual lines emitted so far
        local service_idx=$SCROLL_OFFSET  # index into VISIBLE_SERVICES

        # Mark separator as already consumed if the scroll window starts past
        # the pinned/system boundary (separator scrolled out of view above).
        local sep_rendered=0
        if (( has_separator == 0 || SCROLL_OFFSET > PINNED_COUNT )); then
            sep_rendered=1
        fi

        while (( rendered < available_rows )); do
            # Check: should we insert the separator here?
            if (( sep_rendered == 0 && service_idx == PINNED_COUNT )); then
                _draw_pin_separator
                (( rendered++ ))
                sep_rendered=1
                (( rendered >= available_rows )) && break
            fi

            if (( service_idx >= total_visible )); then
                print_box_line "" "$COLOR_TEXT"
                (( rendered++ ))
                continue
            fi

            local svc="${VISIBLE_SERVICES[$service_idx]}"
            local a_state="${SVC_ACTIVE_STATE[$svc]:-unknown}"
            local u_state="${SVC_UNIT_STATE[$svc]:-unknown}"

            local btn1_label="[start]"
            [[ "$a_state" == "active" ]] && btn1_label="[stop]"
            local btn2_label="[restart]"
            local btn3_label="[enable]"
            [[ "$u_state" == "enabled" ]] && btn3_label="[disable]"

            # ANSI Padding Rule: ALWAYS pad plain text with printf BEFORE applying colors
            local pad_svc pad_act pad_b1 pad_b2 pad_unt pad_b3
            printf -v pad_svc "%-16.16s" "$svc"
            printf -v pad_act "%-12.12s" "$a_state"
            printf -v pad_b1  "%-9.9s"   "$btn1_label"
            printf -v pad_b2  "%-11.11s" "$btn2_label"
            printf -v pad_unt "%-11.11s" "$u_state"
            printf -v pad_b3  "%-9.9s"   "$btn3_label"

            # Apply semantic color styling
            local col_svc="$COLOR_TEXT"
            local is_row_active=0
            if [[ "$FOCUS_AREA" == "services" ]] && (( service_idx == SELECTED_ROW )); then
                is_row_active=1
                col_svc="${COLOR_BOLD}${COLOR_TEXT}"
            fi

            # Pinned rows get a subtle accent tint on the name column
            local pin_prefix=""
            if _is_pinned "$svc"; then
                pin_prefix="${COLOR_ACCENT}"
                col_svc="${pin_prefix}"
                (( is_row_active == 1 )) && col_svc="${COLOR_BOLD}${COLOR_ACCENT}"
            fi

            local col_act="$COLOR_MUTED"
            if [[ "$a_state" == "active" ]]; then
                col_act="$COLOR_SUCCESS"
            elif [[ "$a_state" == "failed" ]]; then
                col_act="${COLOR_ERROR}${COLOR_BOLD}"
            elif [[ "$a_state" =~ ^(activating|reloading|deactivating)$ ]]; then
                col_act="$COLOR_WARN"
            fi

            local col_unt="$COLOR_MUTED"
            if [[ "$u_state" == "enabled" ]]; then
                col_unt="$COLOR_SUCCESS"
            elif [[ "$u_state" == "masked" ]]; then
                col_unt="$COLOR_ERROR"
            elif [[ "$u_state" =~ ^(static|indirect)$ ]]; then
                col_unt="$COLOR_WARN"
            fi

            local col_b1="$COLOR_PRIMARY"
            local col_b2="$COLOR_PRIMARY"
            local col_b3="$COLOR_PRIMARY"

            if (( is_row_active == 1 )); then
                (( SELECTED_BTN == 0 )) && col_b1="$COLOR_HIGHLIGHT"
                (( SELECTED_BTN == 1 )) && col_b2="$COLOR_HIGHLIGHT"
                (( SELECTED_BTN == 2 )) && col_b3="$COLOR_HIGHLIGHT"
            fi

            local row_colored="  ${col_svc}${pad_svc}${COLOR_RESET} ${col_act}${pad_act}${COLOR_RESET} ${col_b1}${pad_b1}${COLOR_RESET} ${col_b2}${pad_b2}${COLOR_RESET} ${col_unt}${pad_unt}${COLOR_RESET} ${col_b3}${pad_b3}${COLOR_RESET} "
            printf '%s%s%s%s%s%s%s\n' \
                "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
                "$row_colored" \
                "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"

            (( service_idx++ ))
            (( rendered++ ))
        done
    fi
}

_draw_scripts_list() {
    local available_rows="$1"

    # Column Header Row
    local p_hdr_name p_hdr_path p_hdr_btn
    printf -v p_hdr_name "%-22.22s" "SCRIPT"
    printf -v p_hdr_path "%-40.40s" "PATH"
    printf -v p_hdr_btn  "%-9.9s"   "ACTION"

    local hdr_content="  ${p_hdr_name} ${p_hdr_path} ${p_hdr_btn} "
    print_box_line "$hdr_content" "$COLOR_SECONDARY$COLOR_BOLD"

    local total_visible=${#VISIBLE_SCRIPTS[@]}
    if (( total_visible == 0 )); then
        print_box_line "  No scripts to be displayed." "$COLOR_MUTED"
        for (( r=1; r < available_rows; r++ )); do
            print_box_line "" "$COLOR_TEXT"
        done
        return 0
    fi

    if (( SCRIPTS_ROW < SCRIPTS_SCROLL_OFFSET )); then
        SCRIPTS_SCROLL_OFFSET=$SCRIPTS_ROW
    elif (( SCRIPTS_ROW >= SCRIPTS_SCROLL_OFFSET + available_rows )); then
        SCRIPTS_SCROLL_OFFSET=$(( SCRIPTS_ROW - available_rows + 1 ))
    fi

    local rendered=0
    local script_idx=$SCRIPTS_SCROLL_OFFSET

    while (( rendered < available_rows )); do
        if (( script_idx >= total_visible )); then
            print_box_line "" "$COLOR_TEXT"
            (( rendered++ ))
            continue
        fi

        local actual_idx="${VISIBLE_SCRIPTS[$script_idx]}"
        local s_name="${SCRIPTS_NAMES[$actual_idx]}"
        local s_path="${SCRIPTS_PATHS[$actual_idx]}"
        local s_btn="[run]"

        local pad_name pad_path pad_btn
        printf -v pad_name "%-22.22s" "$s_name"
        printf -v pad_path "%-40.40s" "$s_path"
        printf -v pad_btn  "%-9.9s"   "$s_btn"

        local col_name="$COLOR_TEXT"
        local col_path="$COLOR_MUTED"
        local col_btn="$COLOR_PRIMARY"

        if [[ "$FOCUS_AREA" == "services" ]] && (( script_idx == SCRIPTS_ROW )); then
            col_name="${COLOR_BOLD}${COLOR_TEXT}"
            col_path="${COLOR_TEXT}"
            col_btn="$COLOR_HIGHLIGHT"
        fi

        local row_colored="  ${col_name}${pad_name}${COLOR_RESET} ${col_path}${pad_path}${COLOR_RESET} ${col_btn}${pad_btn}${COLOR_RESET} "
        printf '%s%s%s%s%s%s%s\n' \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
            "$row_colored" \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"

        (( script_idx++ ))
        (( rendered++ ))
    done
}

draw_ui() {
    # Move to Home without clearing to eliminate screen flicker
    printf '%s' "$TERM_CURSOR_HOME"

    # 1. Application Title Banner (Very Top)
    print_box_top
    local title_str="Linux systemctl manager"
    local left_pad=$(( (INNER_WIDTH - ${#title_str}) / 2 ))
    local right_pad=$(( INNER_WIDTH - ${#title_str} - left_pad ))
    local p_title
    printf -v p_title "%*s%s%*s" "$left_pad" "" "$title_str" "$right_pad" ""
    print_box_line "$p_title" "$COLOR_TITLE$COLOR_BOLD"

    # Divider below Title
    print_box_divider

    # 2. System Action Bar (Below Title)
    if (( SEARCH_MODE == 1 )); then
        local search_prefix="  Search: "
        local cursor_sym="_"
        local used_len=$(( ${#search_prefix} + ${#SEARCH_QUERY} + ${#cursor_sym} ))
        local fill_len=$(( INNER_WIDTH - used_len ))
        (( fill_len < 0 )) && fill_len=0
        local pad_fill
        printf -v pad_fill "%*s" "$fill_len" ""
        local search_line="  ${COLOR_ACCENT}Search: ${COLOR_RESET}${COLOR_BOLD}${COLOR_TEXT}${SEARCH_QUERY}${COLOR_PRIMARY}_${COLOR_RESET}${pad_fill}"
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

        if [[ "$FOCUS_AREA" == "system" ]] || (( HELP_MODE == 1 )); then
            (( SYS_BTN == 0 )) && btn_services_style="$COLOR_HIGHLIGHT" || btn_services_style="$COLOR_PRIMARY"
            (( SYS_BTN == 1 )) && btn_scripts_style="$COLOR_HIGHLIGHT"  || btn_scripts_style="$COLOR_PRIMARY"
            (( SYS_BTN == 2 )) && btn_search_style="$COLOR_HIGHLIGHT"   || btn_search_style="$COLOR_PRIMARY"
            (( SYS_BTN == 3 )) && btn_clear_style="$COLOR_HIGHLIGHT"    || btn_clear_style="$COLOR_PRIMARY"
            (( SYS_BTN == 4 )) && btn_help_style="$COLOR_HIGHLIGHT"     || btn_help_style="$COLOR_PRIMARY"
        else
            if [[ "$CURRENT_VIEW" == "scripts" ]]; then
                btn_scripts_style="${COLOR_BOLD}${COLOR_TEXT}"
            else
                btn_services_style="${COLOR_BOLD}${COLOR_TEXT}"
            fi
        fi

        # Plain char counts: "  Actions:  [services]  [scripts]  [search]  [clear]  [help]" = 60
        local plain_text="  Actions:  [services]  [scripts]  [search]  [clear]  [help]"
        local plain_len=${#plain_text}
        local pad_sys_len=$(( INNER_WIDTH - plain_len ))
        local pad_sys
        printf -v pad_sys "%*s" "$pad_sys_len" ""
        local sys_line="  Actions:  ${btn_services_style}[services]${COLOR_RESET}  ${btn_scripts_style}[scripts]${COLOR_RESET}  ${btn_search_style}[search]${COLOR_RESET}  ${btn_clear_style}[clear]${COLOR_RESET}  ${btn_help_style}[help]${COLOR_RESET}${pad_sys}"

        printf '%s%s%s%s%s%s%s\n' \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET" \
            "$sys_line" \
            "$COLOR_BORDER" "$BOX_V" "$COLOR_RESET"
    fi

    # Divider below System Action Bar
    print_box_divider

    # 3. Main List Area (Middle Main Area)
    local available_rows=$(( TERM_LINES - 15 ))
    (( available_rows < 5 ))  && available_rows=5
    (( available_rows > 15 )) && available_rows=15

    if (( HELP_MODE == 1 )); then
        _draw_help "$available_rows"
    elif [[ "$CURRENT_VIEW" == "scripts" ]]; then
        _draw_scripts_list "$available_rows"
    else
        _draw_services_list "$available_rows"
    fi

    # Divider below Service / Script List Area
    print_box_divider

    # 4. Information Area (Below Main List Area)
    local info_text=""
    if (( HELP_MODE == 1 )); then
        local cur_from=$(( HELP_SCROLL_OFFSET + 1 ))
        local cur_to=$(( HELP_SCROLL_OFFSET + available_rows ))
        (( cur_to > ${#CHEAT_LINES[@]} )) && cur_to=${#CHEAT_LINES[@]}
        info_text="  Information: Keybinding Cheat Sheet (Lines ${cur_from}-${cur_to} of ${#CHEAT_LINES[@]})"
    elif [[ "$CURRENT_VIEW" == "scripts" ]]; then
        if (( ${#VISIBLE_SCRIPTS[@]} > 0 )); then
            local actual_idx="${VISIBLE_SCRIPTS[$SCRIPTS_ROW]}"
            local s_name="${SCRIPTS_NAMES[$actual_idx]}"
            local s_path="${SCRIPTS_PATHS[$actual_idx]}"
            info_text="  Script: ${s_name} | Path: ${s_path}"
        else
            info_text="  Information: No script selected (press [a] to add script)"
        fi
    else
        if (( ${#VISIBLE_SERVICES[@]} > 0 )); then
            local cur_svc="${VISIBLE_SERVICES[$SELECTED_ROW]}"
            if (( INFO_MODE == 0 )); then
                info_text="  Description: ${SVC_DESCRIPTION[$cur_svc]:-No description available}"
            else
                local cpu_val="${CPU_USAGE[$cur_svc]:-0.0}"
                local mem_val="${MEM_USAGE[$cur_svc]:-0.0}"
                local pid_val="${SVC_PID[$cur_svc]:-0}"
                [[ "$pid_val" == "0" ]] && pid_val="None"
                info_text="  Resource Usage: CPU: ${cpu_val}% | Memory: ${mem_val} MB | PID: ${pid_val}"
            fi
        else
            info_text="  Information: No service selected"
        fi
    fi
    print_box_line "$info_text" "$COLOR_ACCENT"

    # Divider below Information Area
    print_box_divider

    # 5. Hint Area (Below Information Area)
    local hint_text="  Hint: $(get_hint_text)"
    print_box_line "$hint_text" "$COLOR_MUTED"

    # Divider below Hint Area
    print_box_divider

    # 6. Status Bar (Bottom Row)
    local col_status="$COLOR_PRIMARY"
    if [[ "$CURRENT_STATUS" =~ "Success" || "$CURRENT_STATUS" =~ "Added" || "$CURRENT_STATUS" =~ "Pinned" ]]; then
        col_status="$COLOR_SUCCESS"
    elif [[ "$CURRENT_STATUS" =~ "Error" || "$CURRENT_STATUS" =~ "Failed" ]]; then
        col_status="${COLOR_ERROR}${COLOR_BOLD}"
    fi
    print_box_line "  ${CURRENT_STATUS}" "$col_status"

    # Bottom Frame Border
    print_box_bottom
}
