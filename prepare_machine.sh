#!/usr/bin/env bash
#
# Prepare the machine for the measurement campaign (PROTOCOL.md, section 6),
# create the campaign directory data/campaign-N and record the state of the
# machine in data/campaign-N/machine_state.txt. N is one above the highest
# campaign number under data/. A campaign directory that holds no results yet,
# left by an earlier run of this script that stopped, is reused.
#
# Run as root from a text console, next to run_campaign.sh:
#
#   sudo ./prepare_machine.sh [CORE]
#
# CORE is the CPU the campaign will be pinned to. By default it is the highest
# numbered online CPU other than 0 once SMT is off.
#
# Every step verifies its result. The script stops at the first step that
# fails and, once the campaign directory exists, records the failure in
# machine_state.txt. All settings are
# volatile: rebooting restores the defaults. Running the script again after a
# failure is safe; steps already done are verified again.
#
# Environment (sudo drops it unless it is given on the sudo command line):
#   FREQ_KHZ   fixed CPU frequency in kHz, used as given, for example
#              sudo FREQ_KHZ=1600000 ./prepare_machine.sh
#              By default it is the highest frequency the cpufreq driver
#              offers, or the next lower one if the measurement core boosts
#              above the highest under load.

set -uo pipefail
shopt -s nullglob
export LC_ALL=C

readonly CPU_SYS=/sys/devices/system/cpu
readonly HWCR=0xc0010015            # AMD hardware configuration register
readonly CPB_DIS_BIT=25             # HWCR[25] disables core performance boost
readonly LOAD_LIMIT=0.5             # 1-minute load average treated as idle
readonly LOAD_WAIT=300              # seconds to wait for the machine to settle
readonly SESSION_WAIT=120           # seconds to wait for sessions to close
readonly FREQ_TOLERANCE_PCT=3       # tolerance of frequency readings under load

# Units stopped for the duration of the campaign. Units that do not exist on
# the machine are skipped. Sockets and timers precede the services they start.
# apt-daily-upgrade.service is deliberately absent: it runs dpkg and must not
# be interrupted, so it is only checked.
readonly UNITS=(
    anacron.timer anacron.service cron.service
    apt-daily.timer apt-daily.service apt-daily-upgrade.timer
    update-notifier-download.timer update-notifier-motd.timer
    motd-news.timer ua-timer.timer ua-messaging.timer
    snapd.snap-repair.timer snapd.socket snapd.service packagekit.service
    fstrim.timer systemd-tmpfiles-clean.timer man-db.timer logrotate.timer
    ondemand.service irqbalance.service
)

# Processes that must not run during the campaign (names as shown by ps,
# truncated to 15 characters).
readonly BUSY_PROCESSES=(
    firefox chrome chromium chromium-browse opera brave vivaldi
    apt apt-get aptitude dpkg unattended-upgr update-manager
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
CAMPAIGN_DIR=""
STATE_FILE=""

REQUESTED_CORE=""
CORE=""
ONLINE=""
VENDOR=""
FREQ=""
PEAK_FREQ=""
BOOSTED=""
IRQ_ON_CPU0=0
IRQ_FIXED=0
CLOSED_SESSIONS=""
BUSY_PID=""
STEP=0
STEP_NAME=""
RESULTS=()
CHECKED_UNITS=()


# ------------------------------------------------------------------ helpers

read_value() {
    cat "$1" 2>/dev/null || true
}

write_value() {
    { printf '%s\n' "$2" > "$1"; } 2>/dev/null
}

# Expand a kernel CPU list such as "0,2-3" into "0 2 3".
parse_cpu_list() {
    local part lo hi c
    local -a parts=() cpus=()
    IFS=',' read -r -a parts <<< "$1"
    for part in "${parts[@]}"; do
        lo="${part%-*}"
        hi="${part#*-}"
        [[ "$lo" =~ ^[0-9]+$ && "$hi" =~ ^[0-9]+$ ]] || continue
        for ((c = lo; c <= hi; c++)); do
            cpus+=("$c")
        done
    done
    echo "${cpus[*]}"
}

begin() {
    STEP=$((STEP + 1))
    STEP_NAME="$1"
    printf '[%2d] %s ... ' "$STEP" "$STEP_NAME"
}

pass() {
    local detail="${1:-}"
    printf 'ok%s\n' "${detail:+ ($detail)}"
    RESULTS+=("[$STEP] $STEP_NAME: ok${detail:+ ($detail)}")
}

fail() {
    local message="$*"
    printf 'FAILED\n     %s\n' "$message"
    RESULTS+=("[$STEP] $STEP_NAME: FAILED ($message)")
    stop_load
    # The state file lives in the campaign directory, which does not exist
    # before step_campaign_dir.
    if [ -n "$STATE_FILE" ]; then
        write_state "failed at step $STEP ($STEP_NAME)"
        printf '\nSetup stopped. The state is recorded in %s\n' "$STATE_FILE"
    else
        printf '\nSetup stopped.\n'
    fi
    exit 1
}

# Print a dot every ten seconds of a long wait, so that it does not look hung.
progress() {
    if [ "$1" -gt 0 ] && [ $(($1 % 10)) -eq 0 ]; then
        printf '.'
    fi
}

stop_load() {
    if [ -n "$BUSY_PID" ]; then
        kill "$BUSY_PID" 2>/dev/null
        wait "$BUSY_PID" 2>/dev/null
        BUSY_PID=""
    fi
}

# Succeed while a unit is running. Oneshot services report "activating"
# rather than "active" while they run.
unit_running() {
    case "$(systemctl is-active "$1" 2>/dev/null)" in
        active|activating|deactivating|reloading) return 0 ;;
    esac
    return 1
}

# Print the IDs of open graphical login sessions.
graphical_sessions() {
    local sid type
    while read -r sid _; do
        [ -n "$sid" ] || continue
        type="$(loginctl show-session "$sid" -p Type --value 2>/dev/null </dev/null)"
        case "$type" in
            x11|wayland|mir) printf '%s ' "$sid" ;;
        esac
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
}

secure_boot_state() {
    local state=""
    if command -v mokutil >/dev/null 2>&1; then
        state="$(mokutil --sb-state 2>/dev/null | head -n 1)"
    fi
    echo "${state:-unknown}"
}

# Set the performance governor and fix both frequency limits to FREQ on every
# online CPU.
apply_frequency() {
    local c d limit
    for c in $ONLINE; do
        d="$CPU_SYS/cpu$c/cpufreq"
        [ -d "$d" ] || fail "cpufreq is not available on CPU $c"
        write_value "$d/scaling_governor" performance \
            || fail "cannot set the governor on CPU $c"
        # The kernel rejects a maximum below the current minimum, which a
        # higher frequency set earlier leaves behind.
        if [ "$(read_value "$d/scaling_min_freq")" -gt "$FREQ" ] 2>/dev/null; then
            write_value "$d/scaling_min_freq" "$FREQ" \
                || fail "cannot set scaling_min_freq on CPU $c"
        fi
        write_value "$d/scaling_max_freq" "$FREQ" \
            || fail "cannot set scaling_max_freq on CPU $c"
        write_value "$d/scaling_min_freq" "$FREQ" \
            || fail "cannot set scaling_min_freq on CPU $c"
        [ "$(read_value "$d/scaling_governor")" = performance ] \
            || fail "the governor on CPU $c is not performance"
        # A firmware limit (bios_limit) caps the maximum below the request.
        limit="$(read_value "$d/bios_limit")"
        [ "$(read_value "$d/scaling_max_freq")" = "$FREQ" ] \
            || fail "scaling_max_freq on CPU $c reads $(read_value "$d/scaling_max_freq")," \
                    "not $FREQ${limit:+; firmware limit $limit kHz}"
        [ "$(read_value "$d/scaling_min_freq")" = "$FREQ" ] \
            || fail "scaling_min_freq on CPU $c reads $(read_value "$d/scaling_min_freq")," \
                    "not $FREQ"
    done
}

# Print the highest frequency the measurement core offers below $1, if any.
next_lower_frequency() {
    local f best=""
    local -a freqs=()
    read -r -a freqs <<< "$(read_value "$CPU_SYS/cpu$CORE/cpufreq/scaling_available_frequencies")"
    for f in "${freqs[@]}"; do
        [[ "$f" =~ ^[0-9]+$ ]] || continue
        [ "$f" -lt "$1" ] || continue
        if [ -z "$best" ] || [ "$f" -gt "$best" ]; then
            best="$f"
        fi
    done
    echo "$best"
}

# Load the measurement core with a busy loop and set PEAK_FREQ to the highest
# frequency it reports.
measure_peak() {
    local cur="$CPU_SYS/cpu$CORE/cpufreq/scaling_cur_freq" value
    PEAK_FREQ=0
    taskset -c "$CORE" sh -c 'while :; do :; done' &
    BUSY_PID=$!
    sleep 3
    for _ in 1 2 3 4 5; do
        value="$(read_value "$cur")"
        [[ "$value" =~ ^[0-9]+$ ]] || fail "cannot read $cur"
        [ "$value" -gt "$PEAK_FREQ" ] && PEAK_FREQ="$value"
        sleep 1
    done
    stop_load
}

find_python() {
    local cand
    for cand in /opt/python3.12/bin/python3.12 /usr/bin/python3.12 /usr/local/bin/python3.12; do
        if [ -x "$cand" ]; then
            echo "$cand"
            return
        fi
    done
    echo "/path/to/python3.12"
}

write_state() {
    local status="$1" c d online bit
    online="$(parse_cpu_list "$(read_value "$CPU_SYS/online")")"
    {
        echo "Machine state for the measurement campaign"
        echo
        echo "written             $(date -Is)"
        echo "status              $status"
        echo "kernel              $(uname -r)"
        echo "cpu                 $(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo)"
        echo "vendor              ${VENDOR:-unknown}"
        echo "online cpus         $(read_value "$CPU_SYS/online")"
        echo "measurement core    ${CORE:-not selected}"
        echo "smt control         $(read_value "$CPU_SYS/smt/control")"
        echo "smt active          $(read_value "$CPU_SYS/smt/active")"
        echo "cpufreq boost       $(read_value "$CPU_SYS/cpufreq/boost")"
        if [ "$VENDOR" = AuthenticAMD ] && command -v rdmsr >/dev/null 2>&1; then
            for c in $online; do
                bit="$(rdmsr -p "$c" -f "$CPB_DIS_BIT:$CPB_DIS_BIT" "$HWCR" 2>/dev/null)" \
                    || bit=unreadable
                echo "cpu$c HWCR[$CPB_DIS_BIT]      $bit"
            done
        fi
        for c in $online; do
            d="$CPU_SYS/cpu$c/cpufreq"
            echo "cpu$c cpufreq        governor=$(read_value "$d/scaling_governor")" \
                "min=$(read_value "$d/scaling_min_freq")" \
                "max=$(read_value "$d/scaling_max_freq")" \
                "cur=$(read_value "$d/scaling_cur_freq")"
        done
        echo "target frequency    ${FREQ:-not set} kHz"
        echo "peak under load     ${PEAK_FREQ:-not measured} kHz"
        if [ -n "$BOOSTED" ]; then
            echo "boost under load    at $BOOSTED"
        elif [ -n "$PEAK_FREQ" ]; then
            echo "boost under load    not observed"
        else
            echo "boost under load    not measured"
        fi
        echo "aslr                $(read_value /proc/sys/kernel/randomize_va_space)"
        echo "nmi watchdog        $(read_value /proc/sys/kernel/nmi_watchdog)"
        echo "console log level   $(read_value /proc/sys/kernel/printk | awk '{ print $1 }')"
        echo "default irq mask    $(read_value /proc/irq/default_smp_affinity)"
        echo "irqs on cpu 0       $IRQ_ON_CPU0"
        echo "irqs not movable    $IRQ_FIXED"
        echo "graphical.target    $(systemctl is-active graphical.target 2>/dev/null)"
        echo "sessions closed     ${CLOSED_SESSIONS:-none}"
        echo "units checked       ${CHECKED_UNITS[*]:-none}"
        echo "load average        $(read_value /proc/loadavg)"
        echo
        echo "Steps"
        printf '%s\n' "${RESULTS[@]}"
    } > "$STATE_FILE" 2>/dev/null
    if [ -n "${SUDO_USER:-}" ]; then
        chown "$SUDO_USER": "$STATE_FILE" 2>/dev/null || true
    fi
}


# -------------------------------------------------------------------- steps

step_preconditions() {
    begin "preconditions"
    local cmd
    [ "$(id -u)" -eq 0 ] || fail "run as root: sudo $0"
    for cmd in systemctl loginctl sysctl dmesg taskset modprobe awk pgrep ps; do
        command -v "$cmd" >/dev/null 2>&1 || fail "required command not found: $cmd"
    done
    [ -r "$CPU_SYS/online" ] || fail "$CPU_SYS/online is not readable"
    [ -f "$SCRIPT_DIR/run_campaign.sh" ] \
        || fail "place this script in the repository root, next to run_campaign.sh"
    if [ -n "$REQUESTED_CORE" ] && ! [[ "$REQUESTED_CORE" =~ ^[0-9]+$ ]]; then
        fail "CORE must be a non-negative integer, got '$REQUESTED_CORE'"
    fi
    VENDOR="$(awk -F': ' '/^vendor_id/ { print $2; exit }' /proc/cpuinfo)"
    case "$VENDOR" in
        AuthenticAMD)
            if ! command -v rdmsr >/dev/null 2>&1 || ! command -v wrmsr >/dev/null 2>&1; then
                fail "msr-tools is not installed: apt install msr-tools"
            fi
            ;;
        GenuineIntel) ;;
        *) fail "unsupported CPU vendor '${VENDOR:-unknown}'" ;;
    esac
    pass "$VENDOR"
}

step_campaign_dir() {
    begin "campaign directory"
    local d n last=0 latest="" detail="reused"
    local -a results=()
    for d in "$DATA_DIR"/campaign-* "$DATA_DIR"/campaigns-*/campaign-*; do
        n="${d##*/campaign-}"
        [ -d "$d" ] && [[ "$n" =~ ^[0-9]+$ ]] || continue
        if [ $((10#$n)) -gt "$last" ]; then
            last=$((10#$n))
            latest="$d"
        fi
    done
    if [ -n "$latest" ] && [ "${latest%/*}" = "$DATA_DIR" ]; then
        results=("$latest"/*.json)
        if [ "${#results[@]}" -eq 0 ]; then
            CAMPAIGN_DIR="$latest"
        fi
    fi
    if [ -z "$CAMPAIGN_DIR" ]; then
        CAMPAIGN_DIR="$DATA_DIR/campaign-$((last + 1))"
        mkdir -p "$CAMPAIGN_DIR" || fail "cannot create $CAMPAIGN_DIR"
        detail="created"
    fi
    # run_campaign.sh writes the results here as the normal user.
    if [ -n "${SUDO_USER:-}" ]; then
        chown "$SUDO_USER": "$DATA_DIR" "$CAMPAIGN_DIR" 2>/dev/null \
            || fail "cannot give $CAMPAIGN_DIR to $SUDO_USER"
    fi
    STATE_FILE="$CAMPAIGN_DIR/machine_state.txt"
    pass "$detail $CAMPAIGN_DIR"
}

step_console_quiet() {
    begin "kernel messages kept off the console"
    dmesg -n 1 2>/dev/null || fail "dmesg -n 1 failed"
    [ "$(read_value /proc/sys/kernel/printk | awk '{ print $1 }')" = 1 ] \
        || fail "the console log level is not 1"
    pass
}

step_mains_power() {
    begin "mains power"
    local supply seen=0 online=0
    for supply in /sys/class/power_supply/*; do
        [ "$(read_value "$supply/type")" = "Mains" ] || continue
        seen=1
        [ "$(read_value "$supply/online")" = "1" ] && online=1
    done
    if [ "$seen" -eq 0 ]; then
        pass "no mains supply reported"
        return
    fi
    [ "$online" -eq 1 ] || fail "running on battery; connect the charger"
    pass "on mains"
}

step_graphical_session() {
    begin "graphical session stopped"
    local sid left waited=0
    if systemctl is-active --quiet graphical.target; then
        case "$(tty 2>/dev/null)" in
            /dev/tty[0-9]*)
                systemctl isolate multi-user.target >/dev/null 2>&1 \
                    || fail "systemctl isolate multi-user.target failed"
                ;;
            *)
                fail "a graphical session is running; switch to a text console" \
                     "(Ctrl+Alt+F3), log in and run the script there"
                ;;
        esac
    fi
    systemctl is-active --quiet graphical.target \
        && fail "graphical.target is still active"
    systemctl is-active --quiet display-manager.service \
        && fail "the display manager is still running"

    # Processes of a desktop session can outlive the display manager; closing
    # the session stops them. A session may also close by itself meanwhile,
    # which makes terminate-session fail harmlessly, so only the outcome is
    # checked.
    CLOSED_SESSIONS="$(graphical_sessions)"
    for sid in $CLOSED_SESSIONS; do
        loginctl terminate-session "$sid" >/dev/null 2>&1
    done
    left="$(graphical_sessions)"
    while [ -n "$left" ]; do
        [ "$waited" -lt "$SESSION_WAIT" ] \
            || fail "graphical sessions still open after $SESSION_WAIT s: ${left% }"
        sleep 1
        waited=$((waited + 1))
        progress "$waited"
        left="$(graphical_sessions)"
    done
    CLOSED_SESSIONS="${CLOSED_SESSIONS% }"
    case "$CLOSED_SESSIONS" in
        '') pass ;;
        *' '*) pass "closed sessions $CLOSED_SESSIONS" ;;
        *) pass "closed session $CLOSED_SESSIONS" ;;
    esac
}

step_processes() {
    begin "no browser or package manager running"
    local unit pattern pid found=""
    local -a pids=()

    # The download phase of the daily apt run is safe to interrupt. The
    # upgrade phase runs dpkg and has to finish on its own.
    for unit in apt-daily.timer apt-daily.service; do
        systemctl cat "$unit" >/dev/null 2>&1 || continue
        systemctl stop "$unit" >/dev/null 2>&1 || fail "cannot stop $unit"
    done
    if unit_running apt-daily-upgrade.service; then
        fail "an unattended upgrade is in progress (apt-daily-upgrade.service);" \
             "wait until it finishes, then run the script again"
    fi

    pattern="$(IFS='|'; echo "${BUSY_PROCESSES[*]}")"
    mapfile -t pids < <(pgrep -x "$pattern" 2>/dev/null)
    for pid in "${pids[@]}"; do
        # The unattended-upgrades shutdown helper idles permanently under the
        # same short name as an upgrade run; it is not package activity.
        if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null \
                | grep -q 'unattended-upgrade-shutdown'; then
            continue
        fi
        found+="$pid $(read_value "/proc/$pid/comm") "
    done
    [ -z "$found" ] || fail "close or wait for: ${found% }"
    pass
}

step_units() {
    begin "background services stopped"
    local unit
    for unit in "${UNITS[@]}"; do
        systemctl cat "$unit" >/dev/null 2>&1 || continue
        systemctl stop "$unit" >/dev/null 2>&1 || fail "cannot stop $unit"
        unit_running "$unit" && fail "$unit is still running"
        CHECKED_UNITS+=("$unit")
    done
    # Its timer is stopped now, but a run may have begun since step_processes.
    unit_running apt-daily-upgrade.service \
        && fail "an unattended upgrade has started (apt-daily-upgrade.service);" \
                "wait until it finishes, then run the script again"
    pass "${#CHECKED_UNITS[@]} units inactive"
}

step_smt() {
    begin "SMT disabled"
    local control="$CPU_SYS/smt/control" state
    [ -e "$control" ] || fail "$control not found; the kernel cannot switch SMT off at run time"
    state="$(read_value "$control")"
    case "$state" in
        off|forceoff|notsupported) ;;
        on)
            write_value "$control" off || fail "writing 'off' to $control failed"
            state="$(read_value "$control")"
            [ "$state" = off ] || fail "$control reads '$state' after writing 'off'"
            ;;
        *) fail "unexpected SMT state '$state'" ;;
    esac
    if [ -e "$CPU_SYS/smt/active" ]; then
        [ "$(read_value "$CPU_SYS/smt/active")" = 0 ] || fail "SMT is still active"
    fi
    pass "$state"
}

step_core() {
    begin "measurement core selected"
    local c
    ONLINE="$(parse_cpu_list "$(read_value "$CPU_SYS/online")")"
    [ -n "$ONLINE" ] || fail "cannot read the list of online CPUs"
    if [ -n "$REQUESTED_CORE" ]; then
        CORE="$REQUESTED_CORE"
    else
        for c in $ONLINE; do
            [ "$c" -ne 0 ] && CORE="$c"
        done
    fi
    [ -n "$CORE" ] || fail "no online CPU other than 0 (online: $ONLINE)"
    [ "$CORE" -ne 0 ] || fail "CPU 0 services interrupts and cannot be the measurement core"
    case " $ONLINE " in
        *" $CORE "*) ;;
        *) fail "CPU $CORE is not online (online: $ONLINE)" ;;
    esac
    pass "CPU $CORE, online: $ONLINE"
}

step_boost() {
    begin "boost controls switched off"
    local boost="$CPU_SYS/cpufreq/boost" c bit value sb detail
    local by_driver="" by_script=""
    if [ -e "$boost" ]; then
        write_value "$boost" 0 || fail "writing 0 to $boost failed"
        [ "$(read_value "$boost")" = 0 ] || fail "$boost does not read 0"
    fi
    case "$VENDOR" in
        AuthenticAMD)
            # Writing 0 to the boost file above makes the cpufreq driver set
            # HWCR[25] itself. The register is written here only where it is
            # still clear, because under Secure Boot the kernel refuses MSR
            # writes from user space while reads remain allowed.
            modprobe msr 2>/dev/null || fail "cannot load the msr module"
            for c in $ONLINE; do
                bit="$(rdmsr -p "$c" -f "$CPB_DIS_BIT:$CPB_DIS_BIT" "$HWCR" 2>/dev/null)" \
                    || fail "cannot read HWCR on CPU $c"
                if [ "$bit" = 1 ]; then
                    by_driver+="$c "
                    continue
                fi
                value="$(rdmsr -p "$c" "$HWCR" 2>/dev/null)" \
                    || fail "cannot read HWCR on CPU $c"
                [[ "$value" =~ ^[0-9a-fA-F]+$ ]] \
                    || fail "unexpected HWCR value '$value' on CPU $c"
                if ! wrmsr -p "$c" "$HWCR" $((0x$value | (1 << CPB_DIS_BIT))) 2>/dev/null; then
                    sb="$(secure_boot_state)"
                    case "$sb" in
                        *enabled*)
                            fail "cannot write HWCR on CPU $c; the kernel refuses MSR" \
                                 "writes while Secure Boot is enabled" ;;
                        *)
                            fail "cannot write HWCR on CPU $c (Secure Boot state: $sb)" ;;
                    esac
                fi
                [ "$(rdmsr -p "$c" -f "$CPB_DIS_BIT:$CPB_DIS_BIT" "$HWCR" 2>/dev/null)" = 1 ] \
                    || fail "HWCR[$CPB_DIS_BIT] is not set on CPU $c"
                by_script+="$c "
            done
            detail="HWCR[$CPB_DIS_BIT] set"
            [ -n "$by_driver" ] && detail+=" by the driver on CPUs ${by_driver% }"
            [ -n "$by_driver" ] && [ -n "$by_script" ] && detail+=","
            [ -n "$by_script" ] && detail+=" by this script on CPUs ${by_script% }"
            ;;
        GenuineIntel)
            if [ -e "$CPU_SYS/intel_pstate/no_turbo" ]; then
                write_value "$CPU_SYS/intel_pstate/no_turbo" 1 \
                    || fail "writing 1 to intel_pstate/no_turbo failed"
                [ "$(read_value "$CPU_SYS/intel_pstate/no_turbo")" = 1 ] \
                    || fail "intel_pstate/no_turbo does not read 1"
            elif [ ! -e "$boost" ]; then
                fail "no turbo control found"
            fi
            detail="turbo disabled"
            ;;
    esac
    pass "$detail"
}

step_frequency() {
    begin "governor and fixed frequency"
    local d available
    local -a freqs=()
    d="$CPU_SYS/cpu$CORE/cpufreq"
    [ -d "$d" ] || fail "cpufreq is not available on CPU $CORE"
    if [ -n "${FREQ_KHZ:-}" ]; then
        FREQ="$FREQ_KHZ"
    else
        available="$(read_value "$d/scaling_available_frequencies")"
        if [ -n "$available" ]; then
            read -r -a freqs <<< "$available"
            FREQ="$(printf '%s\n' "${freqs[@]}" | sort -n | tail -n 1)"
        else
            FREQ="$(read_value "$d/cpuinfo_max_freq")"
        fi
    fi
    [[ "$FREQ" =~ ^[0-9]+$ ]] || fail "cannot determine the target frequency"
    apply_frequency
    pass "performance, $FREQ kHz on CPUs $ONLINE"
}

step_irqs() {
    begin "interrupts moved to CPU 0"
    local f mask
    write_value /proc/irq/default_smp_affinity 1 \
        || fail "cannot set the default interrupt affinity"
    mask="$(read_value /proc/irq/default_smp_affinity | tr -d ',')"
    if ! [[ "$mask" =~ ^[0-9a-fA-F]+$ ]] || [ $((16#$mask)) -ne 1 ]; then
        fail "the default interrupt affinity is '$mask', not CPU 0"
    fi
    # Interrupts managed by the kernel refuse a new affinity; they are counted
    # rather than treated as a failure.
    for f in /proc/irq/*/smp_affinity_list; do
        [ "$(read_value "$f")" = 0 ] || write_value "$f" 0
        if [ "$(read_value "$f")" = 0 ]; then
            IRQ_ON_CPU0=$((IRQ_ON_CPU0 + 1))
        else
            IRQ_FIXED=$((IRQ_FIXED + 1))
        fi
    done
    pass "$IRQ_ON_CPU0 on CPU 0, $IRQ_FIXED managed by the kernel"
}

step_nmi_watchdog() {
    begin "NMI watchdog disabled"
    if [ ! -e /proc/sys/kernel/nmi_watchdog ]; then
        pass "not present"
        return
    fi
    sysctl -q -w kernel.nmi_watchdog=0 >/dev/null 2>&1 \
        || fail "sysctl kernel.nmi_watchdog=0 failed"
    [ "$(read_value /proc/sys/kernel/nmi_watchdog)" = 0 ] \
        || fail "kernel.nmi_watchdog is not 0"
    pass
}

step_aslr() {
    begin "address space layout randomisation enabled"
    if [ "$(read_value /proc/sys/kernel/randomize_va_space)" != 2 ]; then
        sysctl -q -w kernel.randomize_va_space=2 >/dev/null 2>&1 \
            || fail "cannot enable address space layout randomisation"
    fi
    [ "$(read_value /proc/sys/kernel/randomize_va_space)" = 2 ] \
        || fail "kernel.randomize_va_space is not 2"
    pass
}

step_idle() {
    begin "machine idle"
    local waited=0 load busiest blocked
    while :; do
        load="$(cut -d' ' -f1 /proc/loadavg)"
        if awk -v l="$load" -v m="$LOAD_LIMIT" 'BEGIN { exit !(l < m) }'; then
            break
        fi
        if [ "$waited" -ge "$LOAD_WAIT" ]; then
            busiest="$(ps -eo comm= --sort=-pcpu | head -n 3 | tr '\n' ' ')"
            # Tasks in uninterruptible sleep raise the load without using CPU.
            blocked="$(ps -eo stat=,comm= | awk '$1 ~ /^D/ { printf "%s ", $2 }')"
            fail "load average $load stayed above $LOAD_LIMIT for $LOAD_WAIT s;" \
                 "busiest: ${busiest% }${blocked:+; uninterruptible: ${blocked% }}"
        fi
        sleep 5
        waited=$((waited + 5))
        progress "$waited"
    done
    pass "load $load after $waited s"
}

step_frequency_under_load() {
    begin "frequency held under load on CPU $CORE"
    local cur="$CPU_SYS/cpu$CORE/cpufreq/scaling_cur_freq" lower low high c d
    [ -r "$cur" ] || fail "$cur is not readable"
    measure_peak
    # Where boost survives the controls of step_boost, the core is held one
    # frequency lower: the processor boosts only from its highest P-state.
    # An explicit FREQ_KHZ is kept as given.
    if [ "$PEAK_FREQ" -gt $((FREQ + FREQ * FREQ_TOLERANCE_PCT / 100)) ]; then
        BOOSTED="$FREQ kHz, peak $PEAK_FREQ kHz"
        lower="$(next_lower_frequency "$FREQ")"
        if [ -z "${FREQ_KHZ:-}" ] && [ -n "$lower" ]; then
            printf '%s kHz boosted to %s kHz, trying %s kHz ... ' "$FREQ" "$PEAK_FREQ" "$lower"
            FREQ="$lower"
            apply_frequency
            measure_peak
        fi
    fi
    low=$((FREQ - FREQ * FREQ_TOLERANCE_PCT / 100))
    high=$((FREQ + FREQ * FREQ_TOLERANCE_PCT / 100))
    [ "$PEAK_FREQ" -le "$high" ] \
        || fail "CPU $CORE reached $PEAK_FREQ kHz under load, above $FREQ kHz;" \
                "boost is still active"
    [ "$PEAK_FREQ" -ge "$low" ] \
        || fail "CPU $CORE stayed at $PEAK_FREQ kHz under load, below $FREQ kHz;" \
                "a thermal or firmware limit holds it down"
    # A service or a thermal limit may have overridden the settings since
    # step_frequency made them.
    for c in $ONLINE; do
        d="$CPU_SYS/cpu$c/cpufreq"
        if [ "$(read_value "$d/scaling_governor")" != performance ] \
                || [ "$(read_value "$d/scaling_min_freq")" != "$FREQ" ] \
                || [ "$(read_value "$d/scaling_max_freq")" != "$FREQ" ]; then
            fail "the frequency settings of CPU $c changed:" \
                 "governor $(read_value "$d/scaling_governor")," \
                 "min $(read_value "$d/scaling_min_freq")," \
                 "max $(read_value "$d/scaling_max_freq")"
        fi
    done
    pass "peak $PEAK_FREQ kHz at $FREQ kHz${BOOSTED:+; boost at $BOOSTED}"
}

step_record() {
    begin "machine state recorded"
    write_state "complete"
    [ -s "$STATE_FILE" ] || fail "cannot write $STATE_FILE"
    pass "$STATE_FILE"
}


# --------------------------------------------------------------------- main

main() {
    REQUESTED_CORE="${1:-}"
    trap stop_load EXIT
    trap 'fail "interrupted"' INT TERM

    step_preconditions
    step_campaign_dir
    step_console_quiet
    step_mains_power
    step_graphical_session
    step_processes
    step_units
    step_smt
    step_core
    step_boost
    step_frequency
    step_irqs
    step_nmi_watchdog
    step_aslr
    step_idle
    step_frequency_under_load
    step_record

    local py
    py="$(find_python)"
    echo
    echo "The machine is ready. Measurement core: $CORE, fixed frequency: $FREQ kHz"
    echo "Campaign directory: $CAMPAIGN_DIR"
    [ -f "$CAMPAIGN_DIR/PROTOCOL.md" ] \
        || echo "Place the protocol of this campaign there as PROTOCOL.md."
    echo "Next, as your normal user in $SCRIPT_DIR:"
    echo "  PY=$py ./run_campaign.sh $CORE build"
    echo "  PY=$py ./run_campaign.sh $CORE"
    echo "Reboot after the campaign to restore the defaults."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
