# ==============================================================================
# DATA LOADING, FILTERING & REFRESH
# ==============================================================================

load_services() {
    SERVICES=()

    # Config file takes priority when it exists and --no-config is not set
    if (( FLAG_NO_CONFIG == 0 )) && [[ -f "$CONFIG_FILE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            SERVICES+=("${line%.service}")
        done < "$CONFIG_FILE"
        if [[ ${#SERVICES[@]} -gt 0 ]]; then
            return 0
        fi
    fi

    # Fall back to querying systemctl for all installed service units
    local unit_raw
    unit_raw=$(systemctl list-unit-files --type=service --state=enabled,disabled --no-legend --no-pager 2>/dev/null || true)
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" ]] && continue
        local unit_name="${line%% *}"          # first whitespace-delimited field
        [[ "$unit_name" == *@* ]] && continue  # skip template units (e.g. getty@.service)
        unit_name="${unit_name%.service}"      # strip .service suffix
        [[ -z "$unit_name" ]] && continue
        SERVICES+=("$unit_name")
    done <<< "$unit_raw"
}

escape_glob() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\*/\\*}"
    str="${str//\?/\\?}"
    str="${str//\[/\\[}"
    str="${str//\]/\\]}"
    printf '%s' "$str"
}

filter_services() {
    VISIBLE_SERVICES=()
    shopt -s nocasematch
    if [[ -z "$SEARCH_QUERY" ]]; then
        VISIBLE_SERVICES=("${SERVICES[@]}")
    else
        local safe_q
        safe_q=$(escape_glob "$SEARCH_QUERY")
        local pat="*${safe_q}*"
        for s in "${SERVICES[@]}"; do
            local desc="${SVC_DESCRIPTION[$s]:-}"
            if [[ "$s" == $pat || "$desc" == $pat ]]; then
                VISIBLE_SERVICES+=("$s")
            fi
        done
    fi
    shopt -u nocasematch

    if (( ${#VISIBLE_SERVICES[@]} == 0 )); then
        SELECTED_ROW=0
    elif (( SELECTED_ROW >= ${#VISIBLE_SERVICES[@]} )); then
        SELECTED_ROW=$(( ${#VISIBLE_SERVICES[@]} - 1 ))
    fi
}

# 1. Batched Systemd Queries & 2. Batched Process Resource Metrics
refresh_data() {
    for s in "${SERVICES[@]}"; do
        SVC_ACTIVE_STATE["$s"]="unknown"
        SVC_UNIT_STATE["$s"]="unknown"
        SVC_DESCRIPTION["$s"]="Service metadata unavailable"
        SVC_PID["$s"]="0"
        CPU_USAGE["$s"]="0.0"
        MEM_USAGE["$s"]="0.0"
    done

    if [[ ${#SERVICES[@]} -gt 0 ]]; then
        local show_raw
        show_raw=$(systemctl show "${SERVICES[@]}" --property=Id,ActiveState,UnitFileState,Description,MainPID 2>/dev/null || true)

        declare -A block_props=()

        _commit_block() {
            local id="${block_props[Id]:-}"
            [[ -z "$id" ]] && return 0
            local clean_id="${id%.service}"
            local matched_svc=""
            for s in "${SERVICES[@]}"; do
                if [[ "$s" == "$id" || "$s" == "$clean_id" ]]; then
                    matched_svc="$s"
                    break
                fi
            done
            if [[ -n "$matched_svc" ]]; then
                SVC_ACTIVE_STATE["$matched_svc"]="${block_props[ActiveState]:-inactive}"
                SVC_UNIT_STATE["$matched_svc"]="${block_props[UnitFileState]:-disabled}"
                SVC_DESCRIPTION["$matched_svc"]="${block_props[Description]:-No description available}"
                SVC_PID["$matched_svc"]="${block_props[MainPID]:-0}"
            fi
            block_props=()
        }

        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            if [[ -z "$line" ]]; then
                _commit_block
                continue
            fi
            if [[ "$line" == *"="* ]]; then
                local k="${line%%=*}"
                local v="${line#*=}"
                block_props["$k"]="$v"
            fi
        done <<< "$show_raw"
        _commit_block

        local pid_list=""
        for s in "${SERVICES[@]}"; do
            local pid="${SVC_PID[$s]:-0}"
            if [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )); then
                if [[ -z "$pid_list" ]]; then
                    pid_list="$pid"
                else
                    pid_list="${pid_list},${pid}"
                fi
            fi
        done

        if [[ -n "$pid_list" ]]; then
            local ps_raw
            ps_raw=$(ps -o pid=,%cpu=,%mem=,rss= -p "$pid_list" 2>/dev/null || true)
            while IFS= read -r ps_line || [[ -n "$ps_line" ]]; do
                [[ -z "$ps_line" ]] && continue
                read -r r_pid r_cpu r_mem r_rss <<< "$ps_line"
                [[ -z "${r_pid:-}" || ! "$r_pid" =~ ^[0-9]+$ ]] && continue

                local mem_mb="0.0"
                if [[ "$r_rss" =~ ^[0-9]+$ ]] && (( r_rss > 0 )); then
                    local whole=$(( r_rss / 1024 ))
                    local frac=$(( (r_rss * 10 / 1024) % 10 ))
                    mem_mb="${whole}.${frac}"
                fi

                for s in "${SERVICES[@]}"; do
                    if [[ "${SVC_PID[$s]:-0}" == "$r_pid" ]]; then
                        CPU_USAGE["$s"]="$r_cpu"
                        MEM_USAGE["$s"]="$mem_mb"
                    fi
                done
            done <<< "$ps_raw"
        fi
    fi

    filter_services
}
