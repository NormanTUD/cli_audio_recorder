# ═══════════════════════════════════════════════════════════════════════
# 🎙️  audiorec - System-Audio Recorder • MP3 garantiert • kompakt
# ═══════════════════════════════════════════════════════════════════════
audiorec() {
    emulate -L zsh
    setopt local_options no_nomatch pipe_fail

    # ─── Farben ──────────────────────────────────────────────────────
    local ESC; ESC=$(printf '\033')
    local R="${ESC}[0m"       B="${ESC}[1m"       D="${ESC}[2m"
    local RED="${ESC}[38;5;203m"   GRN="${ESC}[38;5;120m"
    local YLW="${ESC}[38;5;222m"   CYN="${ESC}[38;5;117m"
    local MAG="${ESC}[38;5;213m"   ORG="${ESC}[38;5;215m"

    # ─── Guardrails ──────────────────────────────────────────────────
    if ! command -v ffmpeg >/dev/null 2>&1; then
        printf '\n  %s✗%s ffmpeg fehlt: %ssudo apt install ffmpeg%s\n\n' "$RED$B" "$R" "$GRN" "$R"
        return 1
    fi
    if ! command -v pactl >/dev/null 2>&1; then
        printf '\n  %s✗%s pactl fehlt: %ssudo apt install pulseaudio-utils%s\n\n' "$RED$B" "$R" "$GRN" "$R"
        return 1
    fi

    # ─── MP3-Encoder-Strategie bestimmen ────────────────────────────
    # 1. ffmpeg mit libmp3lame  →  am schönsten
    # 2. lame (Standalone)      →  via Pipe, garantiert MP3
    # 3. AAC/m4a Fallback       →  nur wenn beides fehlt
    local mp3_mode=""
    if ffmpeg -hide_banner -h encoder=libmp3lame 2>&1 | grep -q "Encoder libmp3lame"; then
        mp3_mode="ffmpeg"
    elif command -v lame >/dev/null 2>&1; then
        mp3_mode="lame"
    fi

    # ─── System-Audio Devices sammeln ────────────────────────────────
    local -a dev_ids dev_labels
    local -a all_sources
    all_sources=("${(@f)$(pactl list sources short 2>/dev/null | awk '{print $2}')}")
    local n desc
    for n in "${all_sources[@]}"; do
        [[ -z "$n" || "$n" != *.monitor ]] && continue
        desc=$(pactl list sources 2>/dev/null | \
               awk -v want="$n" '
                   /^Source #/ {inblock=0}
                   $1=="Name:" && $2==want {inblock=1; next}
                   inblock && /Description:/ {
                       sub(/^[[:space:]]*Description:[[:space:]]*/, "")
                       print; exit
                   }')
        [[ -z "$desc" ]] && desc="$n"
        dev_ids+=("$n")
        dev_labels+=("$desc")
    done

    if (( ${#dev_ids[@]} == 0 )); then
        printf '\n  %s✗%s Keine System-Audio Quelle (.monitor) gefunden.\n\n' "$RED$B" "$R"
        return 1
    fi

    # ─── Header ──────────────────────────────────────────────────────
    printf '\n  %s🎙  audiorec%s  %s%s%s\n' "$MAG$B" "$R" "$D" "$(pwd)" "$R"

    # ─── Device-Auswahl ──────────────────────────────────────────────
    local chosen chosen_label
    if (( ${#dev_ids[@]} == 1 )); then
        chosen="${dev_ids[1]}"
        chosen_label="${dev_labels[1]}"
        printf '  %s✓%s 🔊 %s\n' "$GRN" "$R" "$chosen_label"
    else
        printf '\n'
        local i
        for (( i=1; i<=${#dev_ids[@]}; i++ )); do
            printf '   %s%d)%s 🔊 %s\n' "$CYN$B" "$i" "$R" "${dev_labels[$i]}"
        done
        local sel
        while true; do
            printf '  %s❯%s Quelle %s[1]%s: ' "$MAG$B" "$R" "$D" "$R"
            if ! read -r sel; then return 1; fi
            [[ "$sel" == "q" ]] && return 0
            [[ -z "$sel" ]] && sel=1
            if [[ "$sel" == <-> ]] && (( sel >= 1 && sel <= ${#dev_ids[@]} )); then
                chosen="${dev_ids[$sel]}"
                chosen_label="${dev_labels[$sel]}"
                break
            fi
        done
    fi

    # ─── Encoder-Args + Extension ────────────────────────────────────
    local ext="mp3"
    local -a codec_args
    case "$mp3_mode" in
        ffmpeg)
            codec_args=(-c:a libmp3lame -b:a 192k)
            ;;
        lame)
            # nur Marker – tatsächliche Encodierung passiert per Pipe
            codec_args=()
            ;;
        "")
            printf '  %s!%s Kein MP3-Encoder. Installiere: %ssudo apt install lame%s\n' \
                   "$YLW$B" "$R" "$GRN" "$R"
            ext="m4a"
            codec_args=(-c:a aac -b:a 192k)
            ;;
    esac

    # ─── Dateiname mit Auto-Increment ────────────────────────────────
    local default_name="audiorecording1"
    if [[ -e "./${default_name}.${ext}" ]]; then
        local counter=2
        while [[ -e "./audiorecording${counter}.${ext}" ]]; do (( counter++ )); done
        default_name="audiorecording${counter}"
    fi

    local user_name
    printf '  %s❯%s Name %s[%s.%s]%s: ' "$MAG$B" "$R" "$D" "$default_name" "$ext" "$R"
    if ! read -r user_name; then return 1; fi
    [[ -z "$user_name" ]] && user_name="$default_name"
    user_name="${user_name%.mp3}"; user_name="${user_name%.m4a}"; user_name="${user_name%.wav}"
    user_name=$(printf '%s' "$user_name" | tr -c '[:alnum:]._ -' '_')
    [[ -z "$user_name" ]] && user_name="$default_name"

    local final_file="./${user_name}.${ext}"

    if [[ -e "$final_file" ]]; then
        local yn
        printf '  %s!%s %s existiert. Überschreiben? %s[y/N]%s: ' \
               "$YLW$B" "$R" "$final_file" "$D" "$R"
        read -r yn
        [[ "$yn" != "y" && "$yn" != "Y" ]] && return 0
    fi

    local raw_file="./.${user_name}.raw.wav"

    # ─── Aufnahme starten ────────────────────────────────────────────
    printf '\n  %s● REC%s → %s  %s(Strg+C = Stop)%s\n\n' \
           "$RED$B" "$R" "$CYN$final_file$R" "$D" "$R"

    local interrupted=0
    trap 'interrupted=1' INT

    ffmpeg -hide_banner -loglevel error -stats \
        -f pulse -i "$chosen" \
        -c:a pcm_s16le -ar 44100 -ac 2 \
        -y "$raw_file"

    trap - INT

    # ─── Roh-Aufnahme prüfen ────────────────────────────────────────
    local raw_sz=0
    [[ -f "$raw_file" ]] && raw_sz=$(wc -c < "$raw_file" 2>/dev/null || echo 0)
    if (( raw_sz < 1000 )); then
        printf '\n  %s✗%s Aufnahme leer.\n\n' "$RED$B" "$R"
        [[ -f "$raw_file" ]] && rm -f "$raw_file"
        return 1
    fi

    # ─── Silence-Trim + Encode ───────────────────────────────────────
    printf '  %s✂  Trimme Stille & encodiere...%s\n' "$ORG" "$R"

    local silence_filter="silenceremove=start_periods=1:start_duration=0.1:start_threshold=-45dB:stop_periods=-1:stop_duration=0.5:stop_threshold=-45dB"
    local ok=0

    if [[ "$mp3_mode" == "lame" ]]; then
        # Getrimmtes WAV aus ffmpeg → in lame pipen
        if ffmpeg -hide_banner -loglevel error \
                -i "$raw_file" -af "$silence_filter" \
                -f wav -c:a pcm_s16le - 2>/dev/null | \
           lame --quiet -b 192 - "$final_file" 2>/dev/null; then
            ok=1
        fi
    else
        if ffmpeg -hide_banner -loglevel error \
                -i "$raw_file" -af "$silence_filter" \
                "${codec_args[@]}" -y "$final_file" 2>/dev/null; then
            ok=1
        fi
    fi

    # Fallback: ohne Trim
    if (( ok == 0 )); then
        printf '  %s!%s Trim fehlgeschlagen – speichere ungetrimmt.\n' "$YLW$B" "$R"
        if [[ "$mp3_mode" == "lame" ]]; then
            ffmpeg -hide_banner -loglevel error -i "$raw_file" \
                -f wav -c:a pcm_s16le - 2>/dev/null | \
                lame --quiet -b 192 - "$final_file" 2>/dev/null
        else
            ffmpeg -hide_banner -loglevel error -i "$raw_file" \
                "${codec_args[@]}" -y "$final_file" 2>/dev/null
        fi
    fi

    rm -f "$raw_file"

    # ─── Ergebnis ────────────────────────────────────────────────────
    local final_sz=0
    [[ -f "$final_file" ]] && final_sz=$(wc -c < "$final_file" 2>/dev/null || echo 0)
    if (( final_sz > 1000 )); then
        local human dur=""
        human=$(du -h "$final_file" 2>/dev/null | cut -f1)
        if command -v ffprobe >/dev/null 2>&1; then
            dur=$(ffprobe -v error -show_entries format=duration \
                  -of default=noprint_wrappers=1:nokey=1 "$final_file" 2>/dev/null | \
                  awk '{printf " · %d:%02d", int($1/60), int($1)%60}')
        fi
        printf '  %s✓%s %s%s%s  %s(%s%s)%s\n\n' \
               "$GRN$B" "$R" "$CYN" "$final_file" "$R" "$D" "$human" "$dur" "$R"
    else
        printf '  %s✗%s Encoding fehlgeschlagen.\n\n' "$RED$B" "$R"
        [[ -f "$final_file" ]] && rm -f "$final_file"
        return 1
    fi
}
