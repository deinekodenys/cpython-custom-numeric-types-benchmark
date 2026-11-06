#!/usr/bin/env bash
#
# Build and measure the minimal class representatives.
#
# The analysis rules are fixed in PROTOCOL.md. Building is a separate
# stage so that compilation never runs immediately before a measurement. Runs
# follow each other without pauses, because any wait would make their
# conditions differ.
#
# Usage:
#   ./run_campaign.sh CORE build     build the representatives
#   ./run_campaign.sh CORE [STAGE]   measure on CPU core CORE (default 3)
#
# Stages: smoke, pilot, campaign, all. The default, all, runs the smoke test,
# the pinning pilot and, after confirmation, the campaign.
#
# Run from the directory of this script. The build record, the results and
# the protocol belong to the campaign directory data/campaign-N that
# prepare_machine.sh created last; it must hold PROTOCOL.md. The built
# extension modules stay next to runner.py.
#
# Environment:
#   CAMPAIGN_DIR     campaign directory (default: data/campaign-N, highest N)
#   PY               CPython 3.12 interpreter (searched for if unset)
#   RUNS             number of campaign runs (default 18)
#   YES=1            continue after the pilot without asking
#   PYTHONHASHSEED   hash seed (default 0)

set -euo pipefail

CORE="${1:-3}"
STAGE="${2:-all}"
RUNS="${RUNS:-18}"
YES="${YES:-0}"

die() {
    echo "error: $*" >&2
    exit 1
}

case "$STAGE" in
    build|smoke|pilot|campaign|all) ;;
    *) die "unknown stage '$STAGE'; expected build, smoke, pilot, campaign or all" ;;
esac

case "$CORE" in
    ''|*[!0-9]*) die "CORE must be a non-negative integer, got '$CORE'" ;;
esac

# ----------------------------------------------------------------- interpreter

if [ -z "${PY:-}" ]; then
    for cand in python3.12 /opt/python3.12/bin/python3.12 /usr/bin/python3.12; do
        if command -v "$cand" >/dev/null 2>&1; then
            PY="$cand"
            break
        fi
    done
fi
[ -n "${PY:-}" ] || die "CPython 3.12 not found; set PY to its path"

VER="$("$PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
[ "$VER" = "3.12" ] || die "$PY is Python $VER; the campaign requires 3.12"

# --------------------------------------------------------------- prerequisites

# The runner works in the campaign directory, so the interpreter must not
# depend on the current directory.
PY="$("$PY" -c 'import sys; print(sys.executable)')"

for f in probe.c measure.py runner.py; do
    [ -f "$f" ] || die "$f not found in the current directory"
done
RUNNER="$PWD/runner.py"

# ---------------------------------------------------------- campaign directory

if [ -z "${CAMPAIGN_DIR:-}" ]; then
    last=-1
    for d in data/campaign-*; do
        n="${d#data/campaign-}"
        [ -d "$d" ] && [[ "$n" =~ ^[0-9]+$ ]] || continue
        if [ $((10#$n)) -gt "$last" ]; then
            last=$((10#$n))
            CAMPAIGN_DIR="$d"
        fi
    done
fi
[ -n "${CAMPAIGN_DIR:-}" ] \
    || die "no campaign directory in data/; run first: sudo ./prepare_machine.sh $CORE"
[ -d "$CAMPAIGN_DIR" ] || die "campaign directory $CAMPAIGN_DIR not found"
CAMPAIGN_DIR="$(cd "$CAMPAIGN_DIR" && pwd)"
[ -f "$CAMPAIGN_DIR/PROTOCOL.md" ] \
    || die "PROTOCOL.md not found in $CAMPAIGN_DIR; place the protocol of this campaign there"
if [ -f "$CAMPAIGN_DIR/campaign.json" ]; then
    die "$CAMPAIGN_DIR already holds a finished campaign; prepare a new one with prepare_machine.sh"
fi
BUILDINFO="$CAMPAIGN_DIR/probe_build.json"

# CPU numbers are not contiguous when SMT siblings are offline, so the core
# is checked against the online set rather than against the CPU count.
ONLINE="$("$PY" -c '
cpus = []
with open("/sys/devices/system/cpu/online") as fh:
    for part in fh.read().strip().split(","):
        lo, _, hi = part.partition("-")
        cpus.extend(range(int(lo), int(hi or lo) + 1))
print(" ".join(map(str, cpus)))
')"
case " $ONLINE " in
    *" $CORE "*) ;;
    *) die "core $CORE is not online; online cores: $ONLINE" ;;
esac
if [ "$CORE" -eq 0 ]; then
    echo "warning: core 0 usually services interrupts; another core is preferable" >&2
fi

# The hash seed is a controlled variable (protocol, section 6). Campaign 3
# ran without it.
export PYTHONHASHSEED="${PYTHONHASHSEED:-0}"

# ----------------------------------------------------------------------- build

# Functions are aligned to 64 bytes in both builds, so the hot code of the two
# modules has the same placement relative to cache lines.
do_build() {
    command -v gcc >/dev/null 2>&1 || die "gcc not found"
    local inc
    inc="$("$PY" -c 'import sysconfig; print(sysconfig.get_paths()["include"])')"
    local -a common=(-O2 -shared -fPIC -falign-functions=64)
    local -a full=("${common[@]}" "-I$inc")
    local -a limited=("${common[@]}" -DLIMITED "-I$inc")

    echo "== building the representatives =="
    echo "  full     gcc ${full[*]} probe.c -o probe_full.so"
    echo "  limited  gcc ${limited[*]} probe.c -o probe_limited.so"
    gcc "${full[@]}" probe.c -o probe_full.so
    gcc "${limited[@]}" probe.c -o probe_limited.so

    "$PY" - "${full[*]}" "${limited[*]}" "$inc" "$PY" >"$BUILDINFO" <<'EOF'
import hashlib
import json
import subprocess
import sys
import time

HOT = ('inobj_add', 'inobj_dealloc', 'tblobj_add', 'tblobj_dealloc')


def md5(path):
    with open(path, 'rb') as fh:
        return hashlib.md5(fh.read()).hexdigest()


def hot_functions(path):
    """Addresses of the hot functions, or None if nm is unavailable."""
    try:
        out = subprocess.run(['nm', path], capture_output=True, text=True,
                             check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    found = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] in HOT:
            found[parts[2]] = int(parts[0], 16)
    return found


cc = subprocess.run(['gcc', '--version'], capture_output=True, text=True)
json.dump({
    'built': time.strftime('%FT%T%z'),
    'cc': 'gcc',
    'cc_version': cc.stdout.splitlines()[0] if cc.stdout else None,
    'flags_full': sys.argv[1],
    'flags_limited': sys.argv[2],
    'include': sys.argv[3],
    'python': sys.argv[4],
    'python_version': sys.version,
    'probe_c_md5': md5('probe.c'),
    'probe_full_md5': md5('probe_full.so'),
    'probe_limited_md5': md5('probe_limited.so'),
    'hot_functions': {name: hot_functions(name + '.so')
                      for name in ('probe_full', 'probe_limited')},
}, sys.stdout, ensure_ascii=False, indent=1)
EOF

    "$PY" - "$BUILDINFO" <<'EOF'
import json
import sys

import probe_full
import probe_limited

for module in (probe_full, probe_limited):
    for cls in (module.InObj, module.TblObj):
        name = f'{cls.__module__}.{cls.__name__}'
        a, b = cls(1.5), cls(2.5)
        if float(a + b) != 4.0:
            sys.exit(f'error: {name} returns a wrong sum')
        refs = sys.getrefcount(cls)
        for _ in range(1000):
            a + b
        if sys.getrefcount(cls) != refs:
            sys.exit(f'error: {name} does not release the reference to its type')
print('== representatives import, add correctly and release their type ==')

with open(sys.argv[1], encoding='utf-8') as fh:
    hot = json.load(fh)['hot_functions']
if any(addrs is None for addrs in hot.values()):
    print('warning: nm not available, function alignment not checked')
else:
    misaligned = [f'{module}.{func}' for module, addrs in hot.items()
                  for func, addr in addrs.items() if addr % 64]
    if misaligned:
        sys.exit('error: not aligned to 64 bytes: ' + ', '.join(misaligned))
    print('== hot functions are aligned to 64 bytes in both builds ==')
EOF

    echo "== build parameters written to $BUILDINFO =="
    echo
    echo "Build complete. Start the measurement with a separate command."
}

# ---------------------------------------------------------- build verification

check_build() {
    [ -f "$BUILDINFO" ] || die "$BUILDINFO not found; run: $0 $CORE build"
    "$PY" - "$BUILDINFO" "$PY" <<'EOF'
import hashlib
import json
import sys


def md5(path):
    with open(path, 'rb') as fh:
        return hashlib.md5(fh.read()).hexdigest()


with open(sys.argv[1], encoding='utf-8') as fh:
    info = json.load(fh)

problems = []
if info.get('probe_c_md5') != md5('probe.c'):
    problems.append('probe.c changed after the build')
for name in ('probe_full', 'probe_limited'):
    try:
        if info.get(name + '_md5') != md5(name + '.so'):
            problems.append(f'{name}.so does not match the recorded build')
    except OSError:
        problems.append(f'{name}.so is missing')
if info.get('python') != sys.argv[2]:
    problems.append(f'built for {info.get("python")}, running {sys.argv[2]}')

if problems:
    print('error: the build does not match its sources', file=sys.stderr)
    for problem in problems:
        print(f'  {problem}', file=sys.stderr)
    print('  run the build stage again', file=sys.stderr)
    sys.exit(1)

print('== build matches its sources ==')
print(f'  full     {info["flags_full"]}')
print(f'  limited  {info["flags_limited"]}')
EOF
}

# --------------------------------------------------------------------- stages

show_env() {
    echo "== environment =="
    echo "  campaign dir    $CAMPAIGN_DIR"
    echo "  interpreter     $PY ($("$PY" -V 2>&1))"
    echo "  core            $CORE (online: $ONLINE)"
    echo "  load average    $(cut -d' ' -f1-3 /proc/loadavg)"
    echo "  protocol md5    $(md5sum "$CAMPAIGN_DIR/PROTOCOL.md" | cut -d' ' -f1)"
    echo "  runner md5      $(md5sum runner.py | cut -d' ' -f1)"
    echo "  measure md5     $(md5sum measure.py | cut -d' ' -f1)"
    echo "  PYTHONHASHSEED  $PYTHONHASHSEED"
    if [ -f "$CAMPAIGN_DIR/machine_state.txt" ]; then
        echo "  machine state   $(md5sum "$CAMPAIGN_DIR/machine_state.txt" | cut -d' ' -f1)"
    else
        echo "warning: machine_state.txt not found in $CAMPAIGN_DIR (protocol, section 6)" >&2
    fi
}

backup_old() {
    local stamp f
    stamp="$(date +%Y%m%d-%H%M%S)"
    for f in smoke.json pilot.json pilot.pinned.json pilot.free.json campaign.json; do
        if [ -f "$CAMPAIGN_DIR/$f" ]; then
            mv "$CAMPAIGN_DIR/$f" "$CAMPAIGN_DIR/${f%.json}.$stamp.json"
            echo "  previous $f kept as ${f%.json}.$stamp.json"
        fi
    done
}

run_smoke() {
    echo
    echo "== smoke test, data not for publication =="
    (cd "$CAMPAIGN_DIR" && "$PY" "$RUNNER" --smoke --runs 6 --out smoke.json)
}

run_pilot() {
    echo
    echo "== pinning pilot =="
    (cd "$CAMPAIGN_DIR" && "$PY" "$RUNNER" --pilot --core "$CORE" --out pilot.json)
}

run_campaign() {
    echo
    echo "== campaign, $RUNS runs =="
    (cd "$CAMPAIGN_DIR" && "$PY" "$RUNNER" --core "$CORE" --runs "$RUNS" --out campaign.json)
}

if [ "$STAGE" = "build" ]; then
    do_build
    exit 0
fi

check_build
show_env
backup_old

case "$STAGE" in
    smoke)    run_smoke ;;
    pilot)    run_pilot ;;
    campaign) run_campaign ;;
    all)
        run_smoke
        run_pilot
        if [ "$YES" != "1" ]; then
            echo
            echo "Pilot complete. Check the relative range of the base case above."
            echo "If it exceeds a few percent, the machine is too noisy and the"
            echo "campaign should be postponed."
            printf "Continue with the campaign? [y/N] "
            read -r answer
            case "$answer" in
                [yY]*) ;;
                *) echo "Stopped after the pilot."; exit 0 ;;
            esac
        fi
        run_campaign
        ;;
esac

echo
echo "== result files in $CAMPAIGN_DIR =="
for f in smoke.json pilot.pinned.json pilot.free.json campaign.json; do
    if [ -f "$CAMPAIGN_DIR/$f" ]; then
        printf "  %-24s %s\n" "$f" "$(md5sum "$CAMPAIGN_DIR/$f" | cut -d' ' -f1)"
    fi
done
