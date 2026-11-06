#!/usr/bin/env python3
"""Measurement campaign for the minimal class representatives.

The driver wraps measure.py without modifying it: bench(), loop_overhead() and
CASES are used as imported. Each run executes in a fresh child process pinned
to one core, the order of the cases within a run follows a Williams design,
and the raw results of all runs are written to a single JSON file.

The analysis rules are fixed in PROTOCOL.md before the campaign starts. The
driver runs in the campaign directory, which holds the protocol,
machine_state.txt, probe_build.json and the results. The MD5 digests of the
protocol, the measurement code, the extension source and the built extension
modules are stored with the results.

Usage:
    runner.py --core 3 --runs 18 --out campaign.json   main campaign
    runner.py --core 3 --pilot --out pilot.json        pinning pilot
    runner.py --smoke --runs 6 --out smoke.json        smoke test
    runner.py --analyze campaign.json                  analyse results
    runner.py --child --order 0,5,1,4,2,3 --seq 0      internal: one run

The smoke test uses reduced N and REPS.
"""

import argparse
import hashlib
import json
import math
import os
import platform
import random
import re
import statistics
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))

# The protocol is kept in the campaign directory, the working directory of
# the driver.
PROTOCOL = 'PROTOCOL.md'

# Class identifiers in the order of measure.CASES.
CLASS_OF = ['base', '3', '4', '5', '6', '7']

# Resampling seed of the bootstrap intervals, fixed by the protocol.
BOOTSTRAP_SEED = 20260824


# ------------------------------------------------------------------ design

def williams(n):
    """Return a Williams square for n treatments.

    Every row is a permutation of range(n). For even n, every ordered pair of
    treatments is adjacent exactly once, which balances first-order carryover.
    """
    first = []
    for j in range(1, n + 1):
        first.append((j + 1) // 2 - 1 if j % 2 else n - j // 2)
    return [[(v + s) % n for v in first] for s in range(n)]


def verify_design(rows, n):
    """Check the balance properties of a design rather than assume them."""
    position = all(sorted(r[p] for r in rows) == list(range(n))
                   for p in range(n))
    latin = all(sorted(r) == list(range(n)) for r in rows)
    pairs = {}
    for r in rows:
        for a, b in zip(r, r[1:]):
            pairs[(a, b)] = pairs.get((a, b), 0) + 1
    counts = set(pairs.values())
    carryover = len(pairs) == n * (n - 1) and counts == {1}
    return {'latin': latin, 'each_case_each_position': position,
            'carryover_balanced': carryover,
            'ordered_pairs_seen': len(pairs),
            'ordered_pairs_possible': n * (n - 1)}


# ---------------------------------------------------------------- affinity

def set_affinity(core):
    out = {'requested': core, 'applied': None, 'actual': None, 'error': None}
    if core is None:
        out['error'] = 'not requested'
    else:
        try:
            os.sched_setaffinity(0, {core})
            out['applied'] = True
        except (AttributeError, OSError, ValueError) as exc:
            out['applied'] = False
            out['error'] = f'{type(exc).__name__}: {exc}'
    try:
        out['actual'] = sorted(os.sched_getaffinity(0))
    except (AttributeError, OSError) as exc:
        out['error'] = (out['error'] or '') + f' getaffinity: {exc}'
    return out


# ------------------------------------------------------------- environment

def _read(path, limit=4096):
    try:
        with open(path, encoding='utf-8', errors='replace') as fh:
            return fh.read(limit).strip()
    except OSError:
        return None


def _run(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return r.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def _md5(path):
    try:
        with open(path, 'rb') as fh:
            return hashlib.md5(fh.read()).hexdigest()
    except OSError:
        return None


def online_cpus():
    """Return the indices of the online CPUs.

    CPU numbers are not contiguous when SMT siblings are offline, so they
    are read from sysfs rather than derived from the CPU count.
    """
    spec = _read('/sys/devices/system/cpu/online')
    if not spec:
        return list(range(os.cpu_count() or 0))
    cpus = []
    for part in spec.split(','):
        lo, _, hi = part.partition('-')
        cpus.extend(range(int(lo), int(hi or lo) + 1))
    return cpus


def cpu_facts():
    info = _read('/proc/cpuinfo', 200000) or ''
    model = next((line.split(':', 1)[1].strip() for line in info.splitlines()
                  if line.startswith('model name')), None)
    flags = next((line.split(':', 1)[1].split() for line in info.splitlines()
                  if line.startswith('flags')), [])
    mhz = [float(m) for m in re.findall(r'cpu MHz\s*:\s*([\d.]+)', info)]
    return {
        'model': model,
        'logical_cores': os.cpu_count(),
        'online_cpus': online_cpus(),
        'mhz_at_capture': mhz,
        'fma': 'fma' in flags,
        'avx2': 'avx2' in flags,
        'avx512f': 'avx512f' in flags,
    }


def freq_facts():
    base = '/sys/devices/system/cpu'
    cpus = online_cpus()
    out = {'cpus': cpus, 'governor': [], 'scaling_cur_khz': [],
           'scaling_min_khz': [], 'scaling_max_khz': []}
    for i in cpus:
        d = f'{base}/cpu{i}/cpufreq'
        for key, fname in (('governor', 'scaling_governor'),
                           ('scaling_cur_khz', 'scaling_cur_freq'),
                           ('scaling_min_khz', 'scaling_min_freq'),
                           ('scaling_max_khz', 'scaling_max_freq')):
            v = _read(f'{d}/{fname}')
            if v is not None:
                out[key].append(v)
    out['smt_control'] = _read(f'{base}/smt/control')
    out['smt_active'] = _read(f'{base}/smt/active')
    out['intel_no_turbo'] = _read(f'{base}/intel_pstate/no_turbo')
    out['cpufreq_boost'] = _read(f'{base}/cpufreq/boost')
    return out


def container_marks():
    cgroup = _read('/proc/1/cgroup') or ''
    return {
        'dockerenv': os.path.exists('/.dockerenv'),
        'cgroup_mentions_container': any(
            k in cgroup for k in ('docker', 'containerd', 'lxc', 'kubepods')),
        'systemd_detect_virt': _run(['systemd-detect-virt']),
        'hypervisor_flag':
            'hypervisor' in (_read('/proc/cpuinfo', 200000) or ''),
    }


def build_facts():
    import sysconfig
    # The protocol belongs to the campaign directory, the code to the
    # directory of this file.
    locations = {'measure.py': HERE, 'probe.c': HERE, 'runner.py': HERE,
                 PROTOCOL: os.getcwd(), 'prepare_machine.sh': HERE}
    sources = {name: _md5(os.path.join(root, name))
               for name, root in locations.items()}
    ext = {}
    for name in ('probe_full', 'probe_limited'):
        for suffix in ('.so', '.abi3.so'):
            for root in (HERE, os.getcwd()):
                p = os.path.join(root, name + suffix)
                if os.path.exists(p):
                    ext[name] = {'path': p, 'md5': _md5(p),
                                 'size': os.path.getsize(p),
                                 'mtime': os.path.getmtime(p)}
    # The build record belongs to the campaign directory.
    probe_build = None
    p = os.path.join(os.getcwd(), 'probe_build.json')
    if os.path.exists(p):
        try:
            with open(p, encoding='utf-8') as fh:
                probe_build = json.load(fh)
        except (OSError, ValueError) as exc:
            probe_build = {'error': f'{type(exc).__name__}: {exc}'}
    return {
        'python': sys.version,
        'implementation': platform.python_implementation(),
        'probe_build': probe_build,
        'gil_disabled': bool(sysconfig.get_config_var('Py_GIL_DISABLED')),
        'cflags': sysconfig.get_config_var('CFLAGS'),
        'cc': sysconfig.get_config_var('CC'),
        'gcc_version': (_run(['gcc', '--version']) or '').splitlines()[:1],
        'libc': ' '.join(platform.libc_ver()),
        'pythonhashseed': os.environ.get('PYTHONHASHSEED'),
        'kernel': platform.platform(),
        'uname': ' '.join(platform.uname()),
        'sources': sources,
        'extensions': ext,
    }


def capture_env():
    return {'cpu': cpu_facts(), 'freq': freq_facts(),
            'container': container_marks(), 'build': build_facts(),
            'machine_state_md5': _md5(os.path.join(os.getcwd(),
                                                   'machine_state.txt')),
            'loadavg': os.getloadavg(), 'captured': time.strftime('%FT%T%z')}


# ----------------------------------------------------------------- one run

def child(order, seq, core, smoke):
    aff = set_affinity(core)  # before the measured modules are imported
    import measure
    if smoke:
        measure.N, measure.REPS = 5000, 3

    if [case.cls for case in measure.CASES] != CLASS_OF:
        raise SystemExit('measure.CASES does not match CLASS_OF')

    load_before = os.getloadavg()
    ov_start = measure.loop_overhead()
    cases = []
    for pos, idx in enumerate(order):
        case = measure.CASES[idx]
        label, med, lo, hi = measure.bench(case.factory, case.label)
        cases.append({'class': case.cls, 'case_index': idx,
                      'position': pos, 'label': label,
                      'median_raw_ns': med,
                      'min_raw_ns': lo, 'max_raw_ns': hi})
    ov_end = measure.loop_overhead()
    load_after = os.getloadavg()

    ov = (ov_start + ov_end) / 2  # protocol, section 3
    for c in cases:
        c['median_ns'] = c['median_raw_ns'] - ov

    return {'seq': seq, 'order': list(order), 'affinity': aff,
            'ov_start_ns': ov_start, 'ov_end_ns': ov_end,
            'ov_drift_ns': ov_end - ov_start, 'ov_used_ns': ov,
            'n': measure.N, 'reps': measure.REPS,
            'load_before': load_before, 'load_after': load_after,
            'cases': cases}


# ------------------------------------------------------------------ driver

def driver(args):
    n = len(CLASS_OF)
    square = williams(n)
    design = verify_design(square, n)
    if not all((design['latin'], design['each_case_each_position'],
                design['carryover_balanced'])):
        raise SystemExit(f'unbalanced design: {design}')

    if args.runs % n:
        print(f'warning: {args.runs} runs is not a multiple of {n}; '
              f'the design is not fully balanced', file=sys.stderr)

    seed = args.seed if args.seed is not None else int(time.time())
    rng = random.Random(seed)
    sequence = []
    while len(sequence) < args.runs:
        block = list(range(n))
        rng.shuffle(block)
        sequence.extend(block)
    sequence = sequence[:args.runs]

    protocol = os.path.abspath(PROTOCOL)
    result = {'protocol_md5': _md5(protocol), 'protocol': protocol,
              'started': time.strftime('%FT%T%z'), 'core': args.core,
              'smoke': args.smoke, 'runs_requested': args.runs,
              'design': {'n': n, 'square': square, 'checks': design,
                         'row_seed': seed, 'row_sequence': sequence},
              'env_before': capture_env(), 'runs': []}

    for k, row_id in enumerate(sequence):
        order = square[row_id]
        cmd = [sys.executable, os.path.abspath(__file__), '--child',
               '--order', ','.join(map(str, order)), '--seq', str(k)]
        if args.core is not None:
            cmd += ['--core', str(args.core)]
        if args.smoke:
            cmd += ['--smoke']
        print(f'  run {k + 1}/{args.runs}, row {row_id}, order {order}',
              file=sys.stderr)
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode:
            raise SystemExit(f'run {k} failed:\n{proc.stderr}')
        run = json.loads(proc.stdout)
        run['row_id'] = row_id
        result['runs'].append(run)

    result['env_after'] = capture_env()
    result['finished'] = time.strftime('%FT%T%z')
    with open(args.out, 'w', encoding='utf-8') as fh:
        json.dump(result, fh, ensure_ascii=False, indent=1)
    print(f'\nraw data: {args.out}', file=sys.stderr)
    return result


def pilot(args):
    """Run six pinned and six unpinned runs and compare the baseline."""
    out = {}
    for tag, core in (('pinned', args.core), ('free', None)):
        sub = argparse.Namespace(**vars(args))
        sub.core, sub.runs = core, 6
        sub.out = args.out.replace('.json', f'.{tag}.json')
        print(f'\npilot, {tag} branch', file=sys.stderr)
        out[tag] = driver(sub)
    for tag, data in out.items():
        r = [c['median_ns'] for run in data['runs'] for c in run['cases']
             if c['class'] == 'base']
        print(f'  {tag}: baseline median {statistics.median(r):.2f} ns, '
              f'range {min(r):.2f} to {max(r):.2f}, '
              f'relative range {(max(r) - min(r)) / statistics.median(r):.1%}')
    return out


# ---------------------------------------------------------------- analysis

def boot_ci(vals, reps=20000, seed=BOOTSTRAP_SEED, level=0.95):
    """Percentile bootstrap interval of the median."""
    rng = random.Random(seed)
    meds = []
    k = len(vals)
    for _ in range(reps):
        meds.append(statistics.median(rng.choices(vals, k=k)))
    meds.sort()
    lo = meds[int((1 - level) / 2 * reps)]
    hi = meds[min(reps - 1, int((1 + level) / 2 * reps))]
    return lo, hi


def analyze(path):
    with open(path, encoding='utf-8') as fh:
        data = json.load(fh)

    print(f'protocol md5 {data["protocol_md5"]}, runs {len(data["runs"])}, '
          f'core {data["core"]}, smoke={data["smoke"]}\n')

    per_run = []
    for run in data['runs']:
        t = {c['class']: c['median_ns'] for c in run['cases']}
        pos = {c['class']: c['position'] for c in run['cases']}
        per_run.append({'t': t, 'pos': pos, 'drift': run['ov_drift_ns'],
                        'aff': run['affinity']['actual']})

    # Rule P2: ratio to the baseline, computed within each run.
    print('ratio to baseline, computed within each run')
    print(f'{"class":8s} {"median ns":>12s} {"ratio":>11s} '
          f'{"ratio range":>20s}')
    for cls in CLASS_OF:
        ns = [r['t'][cls] for r in per_run]
        kk = [r['t'][cls] / r['t']['base'] for r in per_run]
        print(f'{cls:8s} {statistics.median(ns):12.2f} '
              f'{statistics.median(kk):11.3f} '
              f'{min(kk):9.3f} to {max(kk):.3f}')

    # Rules P3 and P4: 2 x 2 design on log ratios, paired within each run.
    #   state placement:        in-object (3, 4) versus external table (5, 7)
    #   level of intervention:  public C API (3, 5) versus limited API (4, 7)
    # A contrast "a -> b" is ln(t_b / t_a).
    d1 = [math.log(r['t']['5'] / r['t']['3']) for r in per_run]
    d2 = [math.log(r['t']['7'] / r['t']['4']) for r in per_run]
    e1 = [math.log(r['t']['3'] / r['t']['4']) for r in per_run]
    e2 = [math.log(r['t']['5'] / r['t']['7']) for r in per_run]
    inter = [a - b for a, b in zip(d1, d2)]
    place = [(a + b) / 2 for a, b in zip(d1, d2)]
    level = [(a + b) / 2 for a, b in zip(e1, e2)]

    print('\n2 x 2 design, paired within each run')
    print(f'{"quantity":39s} {"median":>9s} {"95% bootstrap interval":>24s} '
          f'{"zero":>9s}')
    for name, vals in (('state placement, public C API 3 -> 5', d1),
                       ('state placement, limited API 4 -> 7', d2),
                       ('level of intervention, in-object 4 -> 3', e1),
                       ('level of intervention, table 7 -> 5', e2),
                       ('main effect of state placement', place),
                       ('main effect of level of intervention', level),
                       ('interaction', inter)):
        m = statistics.median(vals)
        lo, hi = boot_ci(vals)
        covers = lo <= 0 <= hi
        print(f'{name:39s} {math.expm1(m):+9.1%} '
              f'{math.expm1(lo):+10.1%} to {math.expm1(hi):<+10.1%} '
              f'{"covered" if covers else "excluded":>9s}')

    lo_i, hi_i = boot_ci(inter)
    print('\nverdict (protocol, rule P4)')
    for name, vals in (('state placement', place),
                       ('level of intervention', level)):
        lo, hi = boot_ci(vals)
        if lo <= 0 <= hi:
            print(f'  {name}: effect not established')
        elif lo_i <= 0 <= hi_i:
            print(f'  {name}: effect present, reported as a single value '
                  f'{math.expm1(statistics.median(vals)):+.1%}')
        else:
            print(f'  {name}: effect present with a significant interaction; '
                  f'report it separately for each level of the other axis')

    # Rule P5: position effect.
    print('\nposition effect, slope of ln t per position')
    for cls in CLASS_OF:
        xs = [r['pos'][cls] for r in per_run]
        ys = [math.log(r['t'][cls]) for r in per_run]
        mx, my = statistics.fmean(xs), statistics.fmean(ys)
        den = sum((x - mx) ** 2 for x in xs)
        cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
        b = cov / den if den else 0.0
        print(f'  class {cls:8s} {math.expm1(b):+7.2%} per position')

    dr = [r['drift'] for r in per_run]
    print(f'\nempty loop drift per run: '
          f'median {statistics.median(dr):+.3f} ns, '
          f'range {min(dr):+.3f} to {max(dr):+.3f}')
    affs = {tuple(r['aff'] or []) for r in per_run}
    print(f'affinity, observed CPU sets: {affs}')


# -------------------------------------------------------------------- main

def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--core', type=int, help='CPU core to pin each run to')
    p.add_argument('--runs', type=int, default=18)
    p.add_argument('--out', default='campaign.json')
    p.add_argument('--seed', type=int,
                   help='seed for shuffling the design rows')
    p.add_argument('--smoke', action='store_true',
                   help='reduced N and REPS')
    p.add_argument('--pilot', action='store_true',
                   help='run the pinning pilot')
    p.add_argument('--analyze', metavar='FILE')
    p.add_argument('--child', action='store_true')
    p.add_argument('--order')
    p.add_argument('--seq', type=int)
    a = p.parse_args()

    if a.child:
        order = [int(v) for v in a.order.split(',')]
        json.dump(child(order, a.seq, a.core, a.smoke), sys.stdout,
                  ensure_ascii=False)
    elif a.analyze:
        analyze(a.analyze)
    elif a.pilot:
        pilot(a)
    else:
        driver(a)
        analyze(a.out)


if __name__ == '__main__':
    main()
