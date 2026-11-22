#!/usr/bin/env bash
# ComfyUI AusBoss Installer for Linux
# Puts a portable ComfyUI, its own Python, ComfyUI-Manager and the AusBoss nodes in one folder.
#
#   bash install.sh [folder]     install (default: ./ComfyUI-AusBoss)
#   bash install.sh --update     update an install (update.sh runs this)
#   options: --yes  don't ask, just install     --device nvidia|amd|intel|cpu
#            --no-shortcut  no app menu entry   --plain  no full-screen view
#   env:     TORCH_INDEX=cu130|cu128|rocm7.1|xpu|cpu   pick the PyTorch build yourself
set -uo pipefail

VERSION="1.0.1"
REPO="ausboss/ComfyUI-AusBoss-Installer"
# Released files, not main, so an install only ever gets a tagged version.
RAW="https://github.com/$REPO/releases/latest/download"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
NEED_GB=15

# ------------------------------------------------------------------ options --
DIR=""; UPDATE=0; YES=0; DEVICE="auto"; SHORTCUT=1; PLAIN=0
ARGS=("$@")
while [ $# -gt 0 ]; do
    case "$1" in
        --update) UPDATE=1 ;;
        -y|--yes) YES=1 ;;
        --device) DEVICE="${2:-}"; shift ;;
        --device=*) DEVICE="${1#*=}" ;;
        --no-shortcut) SHORTCUT=0 ;;
        --plain) PLAIN=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "Unknown option: $1 (try --help)"; exit 1 ;;
        *) DIR="$1" ;;
    esac
    shift
done
case "$DEVICE" in auto|nvidia|amd|intel|cpu) ;; *) echo "Unknown device '$DEVICE' (nvidia, amd, intel or cpu)"; exit 1 ;; esac

# An update first gets the newest released installer, so a fix to the
# installer itself reaches installs made with an older one. Only a newer
# script that parses replaces this one; anything else carries on as it is.
if [ "$UPDATE" = 1 ] && [ -z "${AUSBOSS_INSTALLER_FRESH:-}" ]; then
    SELF="$(readlink -f "${BASH_SOURCE[0]:-$0}")"
    if curl -fsSL --max-time 30 "${AUSBOSS_INSTALLER_URL:-https://github.com/$REPO/releases/latest/download/install.sh}" -o "$SELF.new" 2>/dev/null \
        && bash -n "$SELF.new" 2>/dev/null; then
        LATEST="$(sed -n 's/^VERSION="\([0-9.]*\)"$/\1/p' "$SELF.new" | head -1)"
        if [ -n "$LATEST" ] && [ "$LATEST" != "$VERSION" ] \
            && [ "$(printf '%s\n%s\n' "$VERSION" "$LATEST" | sort -V | tail -1)" = "$LATEST" ]; then
            mv -f "$SELF.new" "$SELF"
            echo "Updated the installer from v$VERSION to v$LATEST."
            AUSBOSS_INSTALLER_FRESH=1 exec bash "$SELF" ${ARGS[@]+"${ARGS[@]}"}
        fi
    fi
    rm -f "$SELF.new"
fi

# --------------------------------------------------------------------- look --
COLOR=0; TRUE=0
if [ -t 1 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR:-}" ]; then COLOR=1; fi
case "${COLORTERM:-}" in truecolor|24bit) TRUE=$COLOR ;; esac
if [ "$TRUE" = 1 ]; then
    teal=$'\e[38;2;0;190;178m'; green=$'\e[38;2;120;214;160m'; amber=$'\e[38;2;245;181;61m'
    rust=$'\e[38;2;235;106;84m'; ink=$'\e[38;2;236;240;238m'; muted=$'\e[38;2;112;126;124m'; faint=$'\e[38;2;62;72;71m'
elif [ "$COLOR" = 1 ]; then
    teal=$'\e[38;5;37m'; green=$'\e[38;5;114m'; amber=$'\e[38;5;214m'
    rust=$'\e[38;5;203m'; ink=$'\e[38;5;255m'; muted=$'\e[38;5;244m'; faint=$'\e[38;5;238m'
else
    teal=""; green=""; amber=""; rust=""; ink=""; muted=""; faint=""
fi
if [ "$COLOR" = 1 ]; then bold=$'\e[1m'; reset=$'\e[0m'; else bold=""; reset=""; fi
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *UTF-8*|*utf8*|*UTF8*|*utf-8*) U=1 ;; *) U=0 ;; esac
if [ "$U" = 1 ]; then
    H="─"; V="│"; TL="╭"; TR="╮"; BL="╰"; BR="╯"; OK="✓"; BAD="✗"; TODO="○"; DOT="·"; ELL="…"; FULL="━"; EMPTY="─"
    SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
else
    H="-"; V="|"; TL="+"; TR="+"; BL="+"; BR="+"; OK="+"; BAD="x"; TODO="o"; DOT="|"; ELL="~"; FULL="#"; EMPTY="-"
    SPIN=('|' '/' '-' '\')
fi

# The full-screen view: only on a real terminal that's big enough
DASH=0; ROWS=24; COLS=80
size() { local s; s="$(stty size 2>/dev/null </dev/tty)" && { ROWS="${s% *}"; COLS="${s#* }"; }; W=$((COLS - 4)); [ $W -gt 80 ] && W=80; [ $W -lt 40 ] && W=40; }
size
[ "$COLOR" = 1 ] && [ "$PLAIN" = 0 ] && [ "$ROWS" -ge 20 ] && [ "$COLS" -ge 60 ] && DASH=1

rep() { local i s=""; for ((i = 0; i < $2; i++)); do s+="$1"; done; printf '%s' "$s"; }
strip() { sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/\x1b\][^\a]*\a//g'; }
fit() { local s="$1" n="$2"; if [ ${#s} -gt "$n" ]; then printf '%s' "${s:0:$((n - 1))}$ELL"; else printf '%s' "$s"; fi; }
fit_end() { local s="$1" n="$2"; if [ ${#s} -gt "$n" ]; then printf '%s' "$ELL${s: -$((n - 1))}"; else printf '%s' "$s"; fi; }

# A color from teal to green, $1 of $2 along
grad() {
    if [ "$TRUE" = 1 ]; then
        local r=$((0 + 120 * $1 / $2)) g=$((190 + 24 * $1 / $2)) b=$((178 - 18 * $1 / $2))
        printf '\e[38;2;%d;%d;%dm' "$r" "$g" "$b"
    else printf '%s' "$teal"; fi
}
LOGO1="▄▀█ █ █ █▀ █▄▄ █▀█ █▀ █▀"; LOGO2="█▀█ █▄█ ▄█ █▄█ █▄█ ▄█ ▄█"
logo_line() {
    local line="$1" i n=${#LOGO1} out=""
    if [ "$U" = 0 ]; then [ "$line" = "$LOGO1" ] && printf '%s' "${teal}${bold}AUSBOSS${reset}" || printf '%s' "       "; return; fi
    for ((i = 0; i < n; i++)); do out+="$(grad "$i" "$n")${line:i:1}"; done
    printf '%s' "$out$reset"
}
L1C="$(logo_line "$LOGO1")"; L2C="$(logo_line "$LOGO2")"
header() {
    printf '\n  %s   %s%sComfyUI Installer%s\n' "$L1C" "$bold" "$ink" "$reset"
    printf '  %s   %s%s%s\n' "$L2C" "$muted" "$1" "$reset"
}

# ---------------------------------------------------------------- the mark --
# The AusBoss mark as pixels: t is teal, a is amber. Each character cell shows two pixels with half blocks.
# shellcheck disable=SC2034  # read through a name reference
MARK_BIG=(
    "....................t..............."
    "....................tt.............."
    "...................ttt.............."
    "..................ttttt............."
    "..................tttttt............"
    ".................ttttttt............"
    "................tttt.tttt..........."
    "................tttt..tttt.........."
    "...............tttt....ttt.........."
    "..............tttt.....tttt........."
    "..............tttt......ttt........."
    ".............tttt...aa...ttt........"
    ".............ttt...aaa...tttt......."
    "............tttt...aaaa...ttt......."
    "...........tttt...aaaaaa..tttt......"
    "...........ttt...aaaaaaa...ttt......"
    "..........tttt.............ttt......"
    ".........tttt.............ttt......."
    ".........ttt....tttttttttttttttt...."
    "........tttt...tttttttttttttttttt..."
    ".......tttt....ttttttttttttttttttt.."
    ".......tttt...................tttt.."
    "......tttt.....................tttt."
    ".....tttt...aaaaaaaaaaaaaaaa...ttttt"
    ".....tttt...aaaaaaaaaaaaaaa....ttttt"
    "....tttt...aaaaaaaaaaaaaaa....ttttt."
    "....ttt....aaaaaaaaaaaaaa....ttttt.."
    "...tttt......................ttttt.."
    "..tttt......................ttttt..."
    "..tttttttttttttttttttttttttttttt...."
    ".tttttttttttttttttttttttttttttt....."
    "ttttttttttttttttttttttttttttttt....."
)
# shellcheck disable=SC2034
MARK_SMALL=(
    "............t........."
    "............tt........"
    "...........ttt........"
    "..........ttttt......."
    "..........tt.ttt......"
    ".........tt...tt......"
    "........ttt....tt....."
    "........tt..a..tt....."
    ".......ttt.aaa..tt...."
    ".......tt..aaaa.tt...."
    "......tt........tt...."
    ".....ttt..tttttttttt.."
    ".....tt..ttttttttttt.."
    "....tt............ttt."
    "...ttt..aaaaaaaaa..ttt"
    "...tt..aaaaaaaaa...ttt"
    "..ttt..aaaaaaaaa..ttt."
    "..tt.............ttt.."
    ".ttttttttttttttttttt.."
    "ttttttttttttttttttt..."
)
MARKS=0
[ "$COLOR" = 1 ] && [ "$U" = 1 ] && [ "$PLAIN" = 0 ] && MARKS=1
if [ "$TRUE" = 1 ]; then
    PX_T="0;190;178"; PX_TL="170;250;240"; PX_A="245;181;61"; PX_AL="255;230;155"; PX_FG="38;2;"; PX_BG="48;2;"
else
    PX_T=37; PX_TL=123; PX_A=214; PX_AL=229; PX_FG="38;5;"; PX_BG="48;5;"
fi
SHIM=-99; LIT_ALL=0; MLINES=()
# The colour of pixel $1 at x=$2, y=$3. Pixels inside the moving highlight (a diagonal band at SHIM) are lit.
px() {
    local lit=$LIT_ALL d
    if [ "$SHIM" -gt -99 ]; then d=$(($2 + $3 - SHIM)); [ $d -ge 0 ] && [ $d -lt 4 ] && lit=1; fi
    if [ "$1" = t ]; then
        if [ "$lit" = 1 ]; then PX=$PX_TL; else PX=$PX_T; fi
    else
        if [ "$lit" = 1 ]; then PX=$PX_AL; else PX=$PX_A; fi
    fi
}
# Turn the pixel array named $1 into lines of text in MLINES
mark_lines() {
    local -n m=$1
    local y x a b pa line r1 r2 nobg=$'\e[49m'
    MLINES=()
    for ((y = 0; y < ${#m[@]}; y += 2)); do
        line=""; r1="${m[y]}"; r2="${m[y + 1]}"
        for ((x = 0; x < ${#r1}; x++)); do
            a="${r1:x:1}"; b="${r2:x:1}"
            if [ "$a" = . ] && [ "$b" = . ]; then line+=" "
            elif [ "$a" = . ]; then px "$b" "$x" $((y + 1)); line+=$'\e['"$PX_FG${PX}m▄"
            elif [ "$b" = . ]; then px "$a" "$x" "$y"; line+=$'\e['"$PX_FG${PX}m▀"
            else
                px "$a" "$x" "$y"; pa=$PX; px "$b" "$x" $((y + 1))
                if [ "$pa" = "$PX" ]; then line+=$'\e['"$PX_FG${pa}m█"
                else line+=$'\e['"$PX_FG$pa;$PX_BG${PX}m▀$nobg"; fi
            fi
        done
        MLINES+=("$line$reset")
    done
}
# The opening: the mark draws in from the top, a highlight sweeps across it and the name appears beside it
splash() {
    if [ "$MARKS" = 0 ] || [ "$COLS" -lt 56 ]; then header "$1"; return; fi
    local name=MARK_BIG
    { [ "$COLS" -lt 84 ] || [ "$ROWS" -lt 30 ]; } && name=MARK_SMALL
    local -n mk=$name
    local n=$((${#mk[@]} / 2)) w=${#mk[0]} r f mid txt frames=20
    SHIM=-99; LIT_ALL=0; mark_lines "$name"; local -a N=("${MLINES[@]}")
    LIT_ALL=1; mark_lines "$name"; local -a L=("${MLINES[@]}"); LIT_ALL=0
    local -a RT=(); for ((r = 0; r < n; r++)); do RT+=(""); done
    mid=$((n / 2 - 2))
    RT[mid]="$L1C"; RT[mid + 1]="$L2C"; RT[mid + 3]="${bold}${ink}ComfyUI Installer${reset}"; RT[mid + 4]="${muted}$1${reset}"
    echo
    if [ -t 1 ] && [ -z "${NO_ANIM:-}" ]; then
        printf '\e[?25l'
        for ((r = 0; r < n; r++)); do
            [ $r -gt 0 ] && printf '\e[1A\r  %s\e[K\n' "${N[r - 1]}"
            printf '  %s\e[K\n' "${L[r]}"; sleep 0.03
        done
        for ((f = 0; f <= frames; f++)); do
            SHIM=$((f * (w + 2 * n + 6) / frames - 5)); mark_lines "$name"
            printf '\e[%dA' "$n"
            for ((r = 0; r < n; r++)); do
                txt=""
                # each line of the name appears a moment after the one above it
                [ -n "${RT[r]}" ] && [ $f -ge $(((r - mid) * 3 + 3)) ] && txt="${RT[r]}"
                printf '\r  %s    %s\e[K\n' "${MLINES[r]}" "$txt"
            done
            sleep 0.035
        done
        SHIM=-99; printf '\e[%dA\e[?25h' "$n"
    fi
    for ((r = 0; r < n; r++)); do printf '\r  %s    %s\e[K\n' "${N[r]}" "${RT[r]}"; done
}

# A box with a title and "key|value" rows
card() {
    local title="$1" color="$2"; shift 2
    local inner=$((W - 2)) row key val pad
    echo "  ${color}${TL}${H} ${reset}${bold}${ink}${title}${reset} ${color}$(rep "$H" $((inner - ${#title} - 3)))${TR}${reset}"
    for row in "$@"; do
        key="${row%%|*}"; val="$(fit_end "${row#*|}" $((inner - 17)))"
        pad=$((inner - 16 - ${#val}))
        printf '  %s%s%s  %s%-12s%s  %s%s%*s%s%s%s\n' "$color" "$V" "$reset" "$muted" "$key" "$reset" "$ink" "$val" "$pad" "" "$color" "$V" "$reset"
    done
    echo "  ${color}${BL}$(rep "$H" "$inner")${BR}${reset}"
}

# ------------------------------------------------------------------- steps --
STEPS=("Tools" "Python" "ComfyUI" "PyTorch" "ComfyUI packages" "Node packs" "Finishing")
WEIGHT=(3 4 8 45 15 20 5)      # share of the bar
EXPECT=(5 20 40 180 60 60 5)   # rough seconds, so the bar moves inside a step
STATE=(); DETAIL=(); WARNED=(); for _ in "${STEPS[@]}"; do STATE+=(todo); DETAIL+=(""); WARNED+=(0); done
CUR=-1; STEP_T0=$SECONDS; T0=$SECONDS; TASK_LABEL=""; TASK_T0=0; FRAME=0
WARNINGS=(); LOG=/dev/null

step_icon() {
    case "${STATE[$1]}" in
        done) printf '%s%s%s' "$green" "$OK" "$reset" ;;
        warn) printf '%s!%s' "$amber" "$reset" ;;
        fail) printf '%s%s%s' "$rust" "$BAD" "$reset" ;;
        run)  printf '%s%s%s' "$teal" "${SPIN[FRAME % ${#SPIN[@]}]}" "$reset" ;;
        *)    printf '%s%s%s' "$faint" "$TODO" "$reset" ;;
    esac
}
SL_IND="    "; SL_DW=0
step_lines() {
    local i name det dw=$((W - 26)); [ "$SL_DW" -gt 0 ] && dw=$SL_DW
    for i in "${!STEPS[@]}"; do
        name="${STEPS[$i]}"; det="${DETAIL[$i]}"
        [ "${STATE[$i]}" = run ] && [ -n "$TASK_LABEL" ] && det="$TASK_LABEL  $((SECONDS - TASK_T0))s"
        case "${STATE[$i]}" in
            todo) printf '%s%s  %s%-18s%s\n' "$SL_IND" "$(step_icon "$i")" "$faint" "$name" "$reset" ;;
            run)  printf '%s%s  %s%s%-18s%s %s%s%s\n' "$SL_IND" "$(step_icon "$i")" "$bold" "$ink" "$name" "$reset" "$teal" "$(fit "$det" "$dw")" "$reset" ;;
            *)    printf '%s%s  %s%-18s%s %s%s%s\n' "$SL_IND" "$(step_icon "$i")" "$ink" "$name" "$reset" "$muted" "$(fit "$det" "$dw")" "$reset" ;;
        esac
    done
}
percent() {
    local i done=0 total=0 part
    for i in "${!WEIGHT[@]}"; do
        total=$((total + WEIGHT[i]))
        case "${STATE[$i]}" in "done"|warn) done=$((done + WEIGHT[i] * 100)) ;; esac
    done
    if [ "$CUR" -ge 0 ] && [ "${STATE[$CUR]}" = run ]; then
        part=$(( (SECONDS - STEP_T0) * 100 / EXPECT[CUR] )); [ $part -gt 95 ] && part=95
        done=$((done + WEIGHT[CUR] * part))
    fi
    echo $((done / total))
}
BARN=0; BARCOL=()
bar() {
    local pct="$1" n=$((W - 20)) fill i out="" el=$((SECONDS - T0))
    if [ "$n" != "$BARN" ]; then BARN=$n; BARCOL=(); for ((i = 0; i < n; i++)); do BARCOL+=("$(grad "$i" "$n")"); done; fi
    fill=$((n * pct / 100))
    for ((i = 0; i < fill; i++)); do out+="${BARCOL[i]}$FULL"; done
    out+="$faint$(rep "$EMPTY" $((n - fill)))$reset"
    printf '  %s  %s%s%3d%%%s  %s%dm %02ds%s\n' "$out" "$bold" "$ink" "$pct" "$reset" "$muted" $((el / 60)) $((el % 60)) "$reset"
}

render() {
    [ "$DASH" = 1 ] || return 0
    size
    local buf="" logn i line w=$((W - 4))
    buf+=$'\e[H'
    if [ "$MARKS" = 1 ] && [ "$COLS" -ge 72 ]; then
        # the mark on the left, a highlight passing over it now and then; the name and the steps beside it
        SHIM=$((FRAME % 80 - 12)); mark_lines MARK_SMALL; SHIM=-99
        local -a top=("${bold}${ink}ComfyUI Installer${reset}" "${muted}v$VERSION $DOT $GPU_SHORT${reset}" "")
        local -a sl=()
        SL_IND=""; SL_DW=$((COLS - 51)); [ $SL_DW -gt 50 ] && SL_DW=50; mapfile -t sl < <(step_lines); SL_IND="    "; SL_DW=0
        top+=("${sl[@]}")
        buf+=$'\n'
        for ((i = 0; i < ${#MLINES[@]}; i++)); do buf+="  ${MLINES[i]}   ${top[i]:-}"$'\n'; done
    else
        buf+="$(header "v$VERSION $DOT $GPU_SHORT")"$'\n\n'
        buf+="$(step_lines)"$'\n'
    fi
    for i in "${WARNINGS[@]+"${WARNINGS[@]}"}"; do buf+="    ${amber}! $(fit "$i" $((W - 6)))${reset}"$'\n'; done
    buf+=$'\n'
    # live output panel, as tall as the window allows
    logn=$((ROWS - 4 - 3 - ${#STEPS[@]} - ${#WARNINGS[@]} - 6)); [ $logn -gt 10 ] && logn=10; [ $logn -lt 2 ] && logn=2
    buf+="  ${faint}${TL}${H} ${reset}${muted}output${reset} ${faint}$(rep "$H" $((W - 11)))${TR}${reset}"$'\n'
    local -a lines=()
    mapfile -t lines < <(tail -n 40 "$LOG" 2>/dev/null | tr '\r' '\n' | strip | grep -v '^\(---\|===\)' | sed 's/^[[:space:]]*//' | grep . | tail -n "$logn")
    for ((i = 0; i < logn; i++)); do
        line="${lines[$i]:-}"; line="$(fit "$line" "$w")"
        buf+="  ${faint}${V}${reset} ${muted}${line}$(rep " " $((w - ${#line})))${reset} ${faint}${V}${reset}"$'\n'
    done
    buf+="  ${faint}${BL}$(rep "$H" $((W - 2)))${BR}${reset}"$'\n\n'
    buf+="$(bar "$(percent)")"
    # clear to the end of each line and below, so nothing old shows through
    printf '%s\e[J' "${buf//$'\n'/$'\e[K\n'}"
}

dash_on()  { [ "$DASH" = 1 ] && printf '\e[?1049h\e[?25l\e[H\e[2J'; return 0; }
dash_off() { [ "$DASH" = 1 ] && printf '\e[?25h\e[?1049l'; DASH=0; return 0; }
# What stays on screen afterwards (under the first card): the checklist and the warnings
report() {
    echo
    step_lines
    local w; for w in "${WARNINGS[@]+"${WARNINGS[@]}"}"; do echo "    ${amber}! $w${reset}"; done
}

end_step() {
    if [ "$CUR" -ge 0 ] && [ "${STATE[$CUR]}" = run ]; then
        if [ "${WARNED[$CUR]}" = 1 ]; then STATE[CUR]="warn"; else STATE[CUR]="done"; fi
    fi
    return 0
}
stage() {
    end_step
    CUR=$((CUR + 1)); STATE[CUR]=run; STEP_T0=$SECONDS; TASK_LABEL=""
    [ "$DASH" = 1 ] || echo $'\n'"  ${teal}${bold}[$((CUR + 1))/${#STEPS[@]}] $1${reset}"
    render
}
ok() {
    DETAIL[CUR]="$1"
    [ "$DASH" = 1 ] || echo "    ${green}${OK}${reset} $1${2:+  ${muted}$2${reset}}"
    render
}
warn() {
    WARNINGS+=("$1"); [ "$CUR" -ge 0 ] && WARNED[CUR]=1
    [ "$DASH" = 1 ] || echo "    ${amber}! $1${reset}"
    render
}
finish_step() { end_step; }

fatal() {
    [ "$CUR" -ge 0 ] && STATE[CUR]=fail
    local was=$DASH; dash_off
    if [ "$was" = 1 ]; then report; fi
    echo
    if [ "$LOG" != /dev/null ]; then
        echo "  ${muted}Last lines of the log:${reset}"
        tail -n 12 "$LOG" | strip | sed "s/^/    ${faint}${V}${reset} ${muted}/; s/\$/${reset}/"
        echo
    fi
    local rows=("Problem|$1")
    [ -n "${2:-}" ] && rows+=("Try|$2")
    [ "$LOG" != /dev/null ] && rows+=("Full log|$LOG")
    card "Install stopped" "$rust" "${rows[@]}"
    echo
    [ -t 0 ] && read -r -p "  Press Enter to exit " _
    exit 1
}

# Run a command, its output going to the log. On the full-screen view the panel shows it live.
task() {
    local label="$1"; shift
    local rc start=$SECONDS
    echo "--- $label: $*" >> "$LOG"
    TASK_LABEL="$label"; TASK_T0=$SECONDS
    if [ "$DASH" = 1 ]; then
        "$@" >> "$LOG" 2>&1 &
        local pid=$!
        while kill -0 "$pid" 2>/dev/null; do FRAME=$((FRAME + 1)); render; sleep 0.12; done
        wait "$pid"; rc=$?
    else
        echo "    ${muted}> $label${reset}"
        "$@" >> "$LOG" 2>&1; rc=$?
    fi
    TASK_LABEL=""
    if [ $rc -eq 0 ]; then ok "$label" "$((SECONDS - start))s"
    elif [ "$DASH" = 0 ]; then
        echo "    ${rust}${BAD} $label${reset}"; tail -n 8 "$LOG" | strip | sed "s/^/      ${muted}/; s/\$/${reset}/"
    fi
    return $rc
}
trap 'dash_off' EXIT
trap 'dash_off; jobs -p | xargs -r kill 2>/dev/null; echo; echo "  Cancelled."; exit 130' INT TERM
trap 'render' WINCH

pkg_hint() {
    if command -v pacman >/dev/null; then echo "sudo pacman -S --needed $*"
    elif command -v apt-get >/dev/null; then echo "sudo apt install $*"
    elif command -v dnf >/dev/null; then echo "sudo dnf install $*"
    elif command -v zypper >/dev/null; then echo "sudo zypper install $*"
    else echo "your package manager: $*"; fi
}

# ---------------------------------------------------------------- preflight --
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ "$UPDATE" = 1 ]; then DIR="${DIR:-$SCRIPT_DIR}"; else DIR="${DIR:-$PWD/ComfyUI-AusBoss}"; fi
[ "$COLOR" = 1 ] && printf '\e]0;%s\a' "ComfyUI AusBoss Installer"
GPU_SHORT="Linux"

[ "$(uname -s)" = Linux ] || fatal "This installer is for Linux." "On Windows run install.bat instead."
[ "$(id -u)" -eq 0 ] && fatal "Don't run the installer as root or with sudo." "Run it as your normal user: bash install.sh"
case "$DIR" in *" "*) fatal "The install path has a space in it." "Pick a folder without spaces, like ~/AI." ;; esac
mkdir -p "$DIR" 2>/dev/null || fatal "Can't create $DIR" "Pick a folder you own, like ~/AI."
DIR="$(cd "$DIR" && pwd)"
[ -w "$DIR" ] || fatal "No permission to write in $DIR"
mkdir -p "$DIR/tools"
LOG="$DIR/install.log"
echo "=== $(date '+%F %T') ComfyUI AusBoss Installer v$VERSION (update=$UPDATE)" >> "$LOG"

MISSING=()
for t in git curl; do command -v "$t" >/dev/null || MISSING+=("$t"); done
[ ${#MISSING[@]} -gt 0 ] && fatal "Missing: ${MISSING[*]}" "$(pkg_hint "${MISSING[@]}")"

export GIT_TERMINAL_PROMPT=0 GIT_LFS_SKIP_SMUDGE=1
# Keep other Python setups (conda, pyenv, mise, venvs) out of this install
unset PYTHONPATH PYTHONHOME VIRTUAL_ENV CONDA_PREFIX CONDA_DEFAULT_ENV UV_PYTHON PIP_REQUIRE_VIRTUALENV
export UV_PYTHON_INSTALL_DIR="$DIR/tools/python" UV_CACHE_DIR="$DIR/tools/uv-cache"
export UV_LINK_MODE=copy UV_HTTP_TIMEOUT=600 UV_PYTHON_PREFERENCE=only-managed

# ----------------------------------------------------------------- hardware --
GPU_NAME=""; GPU_INFO=""; HSA_OVERRIDE=""
NV_DRV="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d '[:space:]')"
HAS_AMD=0; HAS_INTEL=0; AMD_GFX=""
for card in /sys/class/drm/card[0-9]*; do
    case "$card" in *-*) continue ;; esac
    [ -r "$card/device/vendor" ] || continue
    drv="$(basename "$(readlink -f "$card/device/driver" 2>/dev/null)" 2>/dev/null)"
    case "$(cat "$card/device/vendor"):$drv" in
        0x1002:amdgpu) HAS_AMD=1 ;;
        0x8086:xe) HAS_INTEL=1 ;;
        0x8086:i915) case "$(cat "$card/device/device" 2>/dev/null)" in 0x56*|0x7d*|0x64*|0xe2*) HAS_INTEL=1 ;; esac ;;
    esac
done
if [ "$HAS_AMD" = 1 ]; then
    for props in /sys/class/kfd/kfd/topology/nodes/*/properties; do
        v="$(awk '$1=="gfx_target_version"{print $2}' "$props" 2>/dev/null)"
        [ -n "$v" ] && [ "$v" != 0 ] || continue
        AMD_GFX="$(printf 'gfx%d%d%x' $((v / 10000)) $(((v / 100) % 100)) $((v % 100)))"; break
    done
    case "$AMD_GFX" in
        gfx103[1-6]) HSA_OVERRIDE="10.3.0" ;;   # other RDNA2 chips run the gfx1030 code
        gfx1103) HSA_OVERRIDE="11.0.0" ;;       # Radeon 780M/760M
    esac
fi
if [ "$DEVICE" = auto ]; then
    if [ -n "$NV_DRV" ]; then DEVICE=nvidia
    elif [ "$HAS_AMD" = 1 ]; then DEVICE=amd
    elif [ "$HAS_INTEL" = 1 ]; then DEVICE=intel
    else DEVICE=cpu; fi
fi
lspci_name() { lspci 2>/dev/null | grep -iE 'vga|display|3d' | grep -iE "$1" | head -1 | sed 's/^.*: //; s/ (rev .*//'; }
case "$DEVICE" in
    nvidia)
        [ -n "$NV_DRV" ] || fatal "No NVIDIA driver found." "Check that nvidia-smi works in a terminal."
        GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"
        vram="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 | tr -d ' ')"
        GPU_INFO="$((vram / 1024)) GB $DOT driver $NV_DRV"
        if [ "${NV_DRV%%.*}" -ge 580 ]; then AUTO_INDEX=cu130; else AUTO_INDEX=cu128; fi ;;
    amd)   GPU_NAME="$(lspci_name 'amd|ati')"; GPU_INFO="ROCm${AMD_GFX:+ $DOT $AMD_GFX}"; AUTO_INDEX=rocm7.1 ;;
    intel) GPU_NAME="$(lspci_name intel)"; GPU_INFO="Intel XPU"; AUTO_INDEX=xpu ;;
    cpu)   GPU_NAME="no GPU found"; GPU_INFO="runs on the CPU (slow)"; AUTO_INDEX=cpu ;;
esac
GPU_SHORT="${GPU_NAME:-Linux}"; GPU_SHORT="${GPU_SHORT#NVIDIA }"; GPU_SHORT="${GPU_SHORT#GeForce }"
SAVED_INDEX="$(cat "$DIR/tools/torch-index" 2>/dev/null || true)"
TORCH_INDEX="${TORCH_INDEX:-${SAVED_INDEX:-$AUTO_INDEX}}"
FREE_GB=$(( $(df -Pk "$DIR" | awk 'NR==2{print $4}') / 1048576 ))

splash "v$VERSION $DOT Linux"
echo
rows=("Folder|$DIR" "GPU|${GPU_NAME:-unknown}" "|$GPU_INFO" "PyTorch|$TORCH_INDEX build" "Python|$PYTHON_VERSION" "Free space|$FREE_GB GB")
if [ "$UPDATE" = 1 ]; then card "Updating" "$teal" "${rows[@]}"; else card "Ready to install" "$teal" "${rows[@]}"; fi
PRE=()
[ "$DEVICE" = cpu ] && PRE+=("No supported graphics card found. ComfyUI works on the CPU, but slowly.")
[ "$DEVICE" = nvidia ] && [ "$TORCH_INDEX" = cu128 ] && [ "$AUTO_INDEX" = cu128 ] && \
    PRE+=("NVIDIA driver older than 580: using CUDA 12.8. A newer driver gets you newer PyTorch.")
[ "$UPDATE" = 0 ] && [ "$FREE_GB" -lt "$NEED_GB" ] && PRE+=("Only $FREE_GB GB free. The install needs about $NEED_GB GB, plus room for models.")
for w in "${PRE[@]+"${PRE[@]}"}"; do echo "  ${amber}! $w${reset}"; done

if [ "$UPDATE" = 0 ] && [ "$YES" = 0 ] && [ -t 0 ]; then
    echo
    read -r -p "  ${ink}Press ${bold}Enter${reset}${ink} to install, or ${bold}Ctrl+C${reset}${ink} to cancel${reset} " _
fi
WARNINGS=("${PRE[@]+"${PRE[@]}"}")
T0=$SECONDS
dash_on

# ------------------------------------------------------------------- tools --
stage "Tools"
UV="$(command -v uv || true)"
if [ -z "$UV" ]; then
    UV="$DIR/tools/uv/uv"
    if [ ! -x "$UV" ]; then
        get_uv() { curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$DIR/tools/uv" UV_NO_MODIFY_PATH=1 sh; }
        task "Getting uv" get_uv || fatal "Could not download uv." "Check your internet connection."
    fi
fi
ok "git $(git --version | awk '{print $3}') $DOT uv $("$UV" --version | awk '{print $2}')"
uvpip() { "$UV" pip install --python "$PY" "$@"; }

# ------------------------------------------------------------------ python --
stage "Python"
PY="$DIR/venv/bin/python"
if [ ! -x "$PY" ]; then
    task "Setting up Python $PYTHON_VERSION" "$UV" venv --python "$PYTHON_VERSION" --seed "$DIR/venv" \
        || fatal "Could not set up Python."
fi
ok "$("$PY" --version)"

# ----------------------------------------------------------------- comfyui --
stage "ComfyUI"
if [ ! -d "$DIR/ComfyUI/.git" ]; then
    task "Downloading" git clone --progress https://github.com/comfyanonymous/ComfyUI "$DIR/ComfyUI" \
        || fatal "Could not download ComfyUI." "Check your internet connection."
elif [ "$UPDATE" = 1 ]; then
    task "Updating" git -C "$DIR/ComfyUI" pull --ff-only --progress || warn "Could not update ComfyUI (local changes?). Kept the current version."
fi
ok "$(git -C "$DIR/ComfyUI" describe --tags --always 2>/dev/null)"

# ----------------------------------------------------------------- pytorch --
stage "PyTorch"
FIRST_TORCH=1; "$PY" -c "import torch" 2>/dev/null && FIRST_TORCH=0
[ "$FIRST_TORCH" = 1 ] && [ "$DASH" = 0 ] && echo "    ${muted}First time: a few GB to download${reset}"
task "$([ "$FIRST_TORCH" = 1 ] && echo "Downloading a few GB" || echo "Checking") ($TORCH_INDEX)" \
    uvpip torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/$TORCH_INDEX" \
    || fatal "Could not install PyTorch." "Try another build: TORCH_INDEX=cu128 bash install.sh"
echo "$TORCH_INDEX" > "$DIR/tools/torch-index"
ok "$("$PY" -c 'import torch; print(torch.__version__)' 2>/dev/null)"

# Requirements without torch lines, so nothing swaps the GPU build for another one
TORCH_FILTER='^[[:space:]]*(torch|torchvision|torchaudio)([[:space:]<>=!~;\[]|$)'
req_install() {
    local req rc=0; req="$(mktemp)"
    grep -viE "$TORCH_FILTER" "$1" > "$req" || true
    if [ -s "$req" ]; then uvpip -r "$req"; rc=$?; fi
    rm -f "$req"; return $rc
}

stage "ComfyUI packages"
task "ComfyUI requirements" req_install "$DIR/ComfyUI/requirements.txt" || fatal "Could not install ComfyUI's packages."
if [ -f "$DIR/ComfyUI/manager_requirements.txt" ]; then
    task "ComfyUI-Manager" req_install "$DIR/ComfyUI/manager_requirements.txt" || warn "ComfyUI-Manager did not install"
fi
ok "ComfyUI requirements $DOT ComfyUI-Manager"

# ------------------------------------------------------------------- nodes --
stage "Node packs"
NODES="$DIR/nodes.txt"
if [ ! -f "$NODES" ]; then
    if [ -f "$SCRIPT_DIR/nodes.txt" ]; then cp "$SCRIPT_DIR/nodes.txt" "$NODES"
    else curl -fsSL "$RAW/nodes.txt" -o "$NODES" || fatal "Could not download the node list."; fi
fi
# Earlier installers cloned the AusBoss packs under their GitHub names, but
# ComfyUI-Manager keeps them under their Registry names. Two folders mean two
# copies, and an old one can keep loading after every update. An old line in
# a kept nodes.txt still maps to the new folder.
registry_folder() {
    case "$1" in
        ComfyUI-AusBoss) echo ausboss-nodes ;;
        ComfyUI-AusBoss-Model-Downloader) echo ausboss-model-downloader ;;
        *) echo "$1" ;;
    esac
}
# Move an old clone to the Registry folder name. With both folders there,
# the old one is renamed .disabled, which ComfyUI and ComfyUI-Manager skip;
# renaming it back undoes it.
move_old_folder() {
    local base="$1" old="$2" new="$3"
    [ "$old" = "$new" ] || [ ! -d "$base/$old" ] && return 0
    if [ ! -e "$base/$new" ]; then
        mv "$base/$old" "$base/$new" && echo "Moved custom_nodes/$old to custom_nodes/$new"
    else
        local off="$old.disabled" n=2
        while [ -e "$base/$off" ]; do off="$old.$n.disabled"; n=$((n + 1)); done
        mv "$base/$old" "$base/$off" && echo "Turned off the second copy: custom_nodes/$off"
    fi
}
node_get() {
    local url="$1" dest="$2"
    # A folder without .git is a ComfyUI-Manager install: Manager updates it.
    if [ -d "$dest" ] && [ ! -d "$dest/.git" ]; then :
    elif [ ! -d "$dest/.git" ]; then git clone --progress --recursive "$url" "$dest" || return 1
    elif [ "$UPDATE" = 1 ]; then git -C "$dest" pull --ff-only || echo "(could not update, kept the current version)"; fi
    if [ -s "$dest/requirements.txt" ]; then req_install "$dest/requirements.txt" || return 1; fi
    if [ -s "$dest/install.py" ] && [ ! -f "$dest/.installed" ]; then (cd "$dest" && "$PY" install.py) && touch "$dest/.installed"; fi
    return 0
}
PACKS=()
while read -r url name _; do
    { [ -z "${url:-}" ] || [[ "$url" == \#* ]]; } && continue
    name="${name:-$(basename "$url" .git)}"
    old_name="$name"; name="$(registry_folder "$name")"
    stuck=""
    for o in "$old_name" "$(basename "$url" .git)"; do
        move_old_folder "$DIR/ComfyUI/custom_nodes" "$o" "$name" >>"$LOG" 2>&1 || true
        [ "$o" != "$name" ] && [ -d "$DIR/ComfyUI/custom_nodes/$o" ] && stuck="$o"
    done
    # An old folder that could not be moved stays the copy that loads, so
    # cloning a new one beside it would make two. Leave it for the next run.
    if [ -n "$stuck" ]; then
        warn "Could not move custom_nodes/$stuck. Close ComfyUI and run the update again."
        continue
    fi
    if task "$name" node_get "$url" "$DIR/ComfyUI/custom_nodes/$name"; then PACKS+=("$name")
    else warn "$name did not install fully (see install.log)"; fi
done < "$NODES"
task "Extras for the AusBoss nodes" uvpip "pymatting>=1.1" pillow-jxl-plugin || true

if [ "$TORCH_INDEX" != cpu ] && ! "$PY" -c "import torch,sys; sys.exit('+cpu' in torch.__version__)" 2>/dev/null; then
    task "Putting the GPU PyTorch back" uvpip --reinstall torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/$TORCH_INDEX" \
        || warn "PyTorch may be the CPU build now. Run update.sh."
fi
ok "${PACKS[*]:-none}"
finish_step

# ------------------------------------------------------------------ finish --
stage "Finishing"
if [ -f "$SCRIPT_DIR/install.sh" ] && [ "$SCRIPT_DIR" != "$DIR" ]; then cp "$SCRIPT_DIR/install.sh" "$DIR/install.sh.new"
elif [ "$SCRIPT_DIR" != "$DIR" ]; then curl -fsSL "$RAW/install.sh" -o "$DIR/install.sh.new" || true; fi
# a new file, not an overwrite, so a running copy keeps reading its old one
[ -s "$DIR/install.sh.new" ] && mv -f "$DIR/install.sh.new" "$DIR/install.sh"
[ -f "$DIR/extra_args.txt" ] || printf '%s\n' "# Extra ComfyUI startup options. Remove --auto-launch to stop the browser opening." "--auto-launch" > "$DIR/extra_args.txt"

cat > "$DIR/start.sh.new" <<EOF
#!/usr/bin/env bash
# Start ComfyUI. Extra options go in extra_args.txt or after the command.
cd "\$(dirname "\$(readlink -f "\$0")")" || exit 1
${HSA_OVERRIDE:+export HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE}
ARGS=\$(grep -v '^[[:space:]]*#' extra_args.txt 2>/dev/null | tr '\n' ' ')
cd ComfyUI || exit 1
# shellcheck disable=SC2086
exec ../venv/bin/python main.py --enable-manager \$ARGS "\$@"
EOF
cat > "$DIR/update.sh.new" <<'EOF'
#!/usr/bin/env bash
# Update ComfyUI, its packages and every pack in nodes.txt.
cd "$(dirname "$(readlink -f "$0")")" || exit 1
exec bash install.sh --update "$@"
EOF
for f in start.sh update.sh; do chmod +x "$DIR/$f.new" && mv -f "$DIR/$f.new" "$DIR/$f"; done
DONE_BITS="start.sh $DOT update.sh"

if [ "$SHORTCUT" = 1 ] && [ "$UPDATE" = 0 ] && [ -d "$HOME/.local/share" ]; then
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/comfyui-ausboss.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ComfyUI (AusBoss)
Comment=Start ComfyUI
Exec=$DIR/start.sh
Path=$DIR
Terminal=true
Categories=Graphics;
EOF
    DONE_BITS+=" $DOT app menu entry"
fi

TASK_LABEL="Checking PyTorch"; render
GPU_OK="$("$PY" -c "
import torch
a = torch.cuda.is_available() or (hasattr(torch, 'xpu') and torch.xpu.is_available())
print(torch.__version__ + ('|yes' if a else '|no'))" 2>>"$LOG")"
TASK_LABEL=""
TV="${GPU_OK%%|*}"
if [ -z "$GPU_OK" ]; then warn "PyTorch did not load. Run update.sh, and see install.log."
elif [ "${GPU_OK##*|}" = yes ]; then DONE_BITS+=" $DOT GPU ready"
elif [ "$DEVICE" != cpu ]; then warn "PyTorch $TV can't see the GPU. Check the driver, then run update.sh."
fi
ok "$DONE_BITS"
finish_step
render; [ "$DASH" = 1 ] && sleep 0.6

# ----------------------------------------------------------------- summary --
T=$((SECONDS - T0))
dash_off
report
echo
rows=("Took|$((T / 60))m $((T % 60))s" "Start|$DIR/start.sh" "Open|http://127.0.0.1:8188" "Models|$DIR/ComfyUI/models" "Update|$DIR/update.sh" "Log|$LOG")
if [ "$UPDATE" = 1 ]; then card "ComfyUI is up to date" "$green" "${rows[@]}"; else card "ComfyUI is ready" "$green" "${rows[@]}"; fi
echo

if [ "$YES" = 0 ] && [ -t 0 ] && [ "$UPDATE" = 0 ]; then
    read -r -p "  ${ink}Start ComfyUI now? ${bold}[Y/n]${reset} " a
    case "${a:-y}" in [Yy]*) exec "$DIR/start.sh" ;; esac
fi
