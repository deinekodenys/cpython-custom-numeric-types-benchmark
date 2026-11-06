#!/usr/bin/env python3
"""Post hoc analyses that runner.py --analyze does not report.

Three analyses are printed:

  * sensitivity analysis: the ratio table and the 2 x 2 design repeated
    without the runs that contain a slow case, a case being slow when its
    median exceeds the median of its class by more than a quarter;
  * absolute differences between classes in nanoseconds, as medians of the
    within-run differences over all runs;
  * tier gap: the median ratio of class 6 divided by the median ratio of
    each C class.

None of these analyses is part of the pre-registered protocol. Removing runs
breaks the balance of the Williams design, so the sensitivity analysis
measures the influence of the slow cases and is not a primary result.
Intervals come from runner.boot_ci and use the same seed, number of
resamples and confidence level as the pre-registered analysis.

Usage:
    post_hoc.py campaign.json
    post_hoc.py campaign.json --exclude 7,11,17

runner.py must be importable, for example from the same directory.
"""

import argparse
import hashlib
import json
import math
import os
import statistics
import sys

import runner

# A case is slow when its median exceeds its class median by this factor.
SLOW_FACTOR = 1.25

# Same confidence level as the effect intervals reported by runner.analyze.
LEVEL = 0.95

C_CLASSES = ('3', '4', '5', '7')
PYTHON_CLASS = '6'


def file_md5(path):
    """Return the hexadecimal MD5 digest of a file."""
    with open(path, 'rb') as fh:
        return hashlib.md5(fh.read()).hexdigest()


def load_runs(path):
    """Return a list of (seq, times) pairs, one per run.

    times maps each class identifier to the net median time in ns.
    """
    with open(path, encoding='utf-8') as fh:
        data = json.load(fh)
    runs = []
    for index, run in enumerate(data['runs']):
        seq = run.get('seq', index)
        times = {c['class']: c['median_ns'] for c in run['cases']}
        missing = set(runner.CLASS_OF) - times.keys()
        if missing:
            raise SystemExit(f'run {seq}: missing classes {sorted(missing)}')
        runs.append((seq, times))
    return runs


def slow_cases(runs):
    """Return (seq, class, time, class median) for every slow case."""
    found = []
    for cls in runner.CLASS_OF:
        median = statistics.median(t[cls] for _, t in runs)
        found.extend((seq, cls, t[cls], median) for seq, t in runs
                     if t[cls] > SLOW_FACTOR * median)
    return sorted(found)


def design_contrasts(runs):
    """Return (name, values) for the contrasts of the 2 x 2 design.

    The contrasts are those of runner.analyze: a contrast "a -> b" is
    ln(t_b / t_a), paired within each run.
    """
    d1 = [math.log(t['5'] / t['3']) for _, t in runs]
    d2 = [math.log(t['7'] / t['4']) for _, t in runs]
    e1 = [math.log(t['3'] / t['4']) for _, t in runs]
    e2 = [math.log(t['5'] / t['7']) for _, t in runs]
    return [
        ('state placement, public C API 3 -> 5', d1),
        ('state placement, limited API 4 -> 7', d2),
        ('level of intervention, in-object 4 -> 3', e1),
        ('level of intervention, table 7 -> 5', e2),
        ('main effect of state placement',
         [(a + b) / 2 for a, b in zip(d1, d2)]),
        ('main effect of level of intervention',
         [(a + b) / 2 for a, b in zip(e1, e2)]),
        ('interaction', [a - b for a, b in zip(d1, d2)]),
    ]


def absolute_differences(runs):
    """Return (name, values) for within-run differences in ns."""
    limited_in_object = [t['4'] - t['3'] for _, t in runs]
    limited_table = [t['7'] - t['5'] for _, t in runs]
    return [
        ('limited API, in-object 3 -> 4', limited_in_object),
        ('limited API, table 5 -> 7', limited_table),
        ('difference of the two increments',
         [a - b for a, b in zip(limited_in_object, limited_table)]),
        ('external table, public C API 3 -> 5',
         [t['5'] - t['3'] for _, t in runs]),
        ('external table, limited API 4 -> 7',
         [t['7'] - t['4'] for _, t in runs]),
    ]


def tier_gaps(runs):
    """Return the median ratio of class 6 over that of each C class."""
    def median_ratio(cls):
        return statistics.median(t[cls] / t['base'] for _, t in runs)

    python_tier = median_ratio(PYTHON_CLASS)
    return {cls: python_tier / median_ratio(cls) for cls in C_CLASSES}


def print_ratio_table(runs):
    """Print the median time, median ratio and ratio range per class."""
    print('ratio to baseline, computed within each run')
    print(f'{"class":8s} {"median ns":>12s} {"ratio":>11s} '
          f'{"ratio range":>20s}')
    for cls in runner.CLASS_OF:
        ns = [t[cls] for _, t in runs]
        ratios = [t[cls] / t['base'] for _, t in runs]
        print(f'{cls:8s} {statistics.median(ns):12.2f} '
              f'{statistics.median(ratios):11.3f} '
              f'{min(ratios):9.3f} to {max(ratios):.3f}')


def print_design(runs):
    """Print the median contrasts of the 2 x 2 design with intervals."""
    print('2 x 2 design, paired within each run')
    print(f'{"quantity":39s} {"median":>9s} '
          f'{f"{LEVEL:.0%} bootstrap interval":>24s} {"zero":>9s}')
    for name, values in design_contrasts(runs):
        lo, hi = runner.boot_ci(values, level=LEVEL)
        zero = 'covered' if lo <= 0 <= hi else 'excluded'
        print(f'{name:39s} {math.expm1(statistics.median(values)):+9.1%} '
              f'{math.expm1(lo):+10.1%} to {math.expm1(hi):<+10.1%} '
              f'{zero:>9s}')


def print_differences(runs):
    """Print the median absolute differences with intervals."""
    print(f'absolute differences in ns, median of within-run differences, '
          f'{len(runs)} runs')
    print(f'{"quantity":39s} {"median":>9s} '
          f'{f"{LEVEL:.0%} bootstrap interval":>24s}')
    for name, values in absolute_differences(runs):
        lo, hi = runner.boot_ci(values, level=LEVEL)
        print(f'{name:39s} {statistics.median(values):+9.2f} '
              f'{lo:+10.2f} to {hi:+.2f}')


def print_tier_gaps(runs):
    """Print the tier gap for each C class and its range."""
    gaps = tier_gaps(runs)
    print(f'tier gap, median ratio of class {PYTHON_CLASS} over that of '
          f'each C class, {len(runs)} runs')
    for cls, gap in gaps.items():
        print(f'  {PYTHON_CLASS} / {cls}  {gap:7.3f}')
    print(f'  range  {min(gaps.values()):.3f} to {max(gaps.values()):.3f}')


def run_numbers(text):
    """Parse a comma-separated list of run numbers."""
    try:
        return {int(item) for item in text.split(',') if item.strip()}
    except ValueError:
        raise argparse.ArgumentTypeError(
            f'expected comma-separated run numbers, got {text!r}') from None


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('results', help='campaign results file (JSON)')
    parser.add_argument('--exclude', type=run_numbers, metavar='SEQ,...',
                        help='runs to leave out of the sensitivity analysis '
                             'instead of the runs with slow cases')
    args = parser.parse_args(argv)

    runs = load_runs(args.results)
    print(f'results md5 {file_md5(args.results)}, '
          f'runner.py md5 {file_md5(os.path.abspath(runner.__file__))}, '
          f'seed {runner.BOOTSTRAP_SEED}, runs {len(runs)}\n')

    if args.exclude is None:
        slow = slow_cases(runs)
        print(f'slow cases, case median above {SLOW_FACTOR:g} x class median')
        for seq, cls, time, median in slow:
            print(f'  run {seq:3d}  class {cls:5s} {time:9.2f} ns, '
                  f'class median {median:.2f} ns')
        if not slow:
            print('  none')
        excluded = {seq for seq, _, _, _ in slow}
    else:
        unknown = args.exclude - {seq for seq, _ in runs}
        if unknown:
            parser.error(f'no such runs: {sorted(unknown)}')
        excluded = args.exclude

    kept = [(seq, t) for seq, t in runs if seq not in excluded]
    listed = ', '.join(str(seq) for seq in sorted(excluded)) or 'none'
    print(f'\nsensitivity analysis, {len(kept)} runs, excluded: {listed}\n')
    print_ratio_table(kept)
    print()
    print_design(kept)
    print()
    print_differences(runs)
    print()
    print_tier_gaps(runs)
    return 0


if __name__ == '__main__':
    sys.exit(main())
