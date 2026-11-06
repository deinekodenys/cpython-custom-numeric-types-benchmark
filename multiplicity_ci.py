#!/usr/bin/env python3
"""Bootstrap confidence intervals for the median ratio to the baseline.

For each class, runner.py --analyze reports the median of the within-run
ratios to the baseline together with their range. This script adds a
percentile bootstrap confidence interval for that median. It reuses
runner.boot_ci, so the resampling seed, the number of resamples and the
confidence level match those of the effect intervals.

The interval is a post hoc addition and is not part of the pre-registered
analysis. It reflects run-to-run variation only; systematic errors, such as
a bias in the empty-loop correction, are not covered.

Usage:
    multiplicity_ci.py campaign.json

runner.py must be importable, for example from the same directory.
"""

import argparse
import hashlib
import json
import os
import statistics
import sys

import runner

# Same confidence level as the effect intervals reported by runner.analyze.
LEVEL = 0.95


def file_md5(path):
    """Return the hexadecimal MD5 digest of a file."""
    with open(path, 'rb') as fh:
        return hashlib.md5(fh.read()).hexdigest()


def load_runs(path):
    """Return the net median time of every class, one mapping per run."""
    with open(path, encoding='utf-8') as fh:
        data = json.load(fh)
    runs = []
    for index, run in enumerate(data['runs']):
        times = {c['class']: c['median_ns'] for c in run['cases']}
        missing = set(runner.CLASS_OF) - times.keys()
        if missing:
            raise SystemExit(f'run {run.get("seq", index)}: '
                             f'missing classes {sorted(missing)}')
        runs.append(times)
    return runs


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('results', help='campaign results file (JSON)')
    args = parser.parse_args(argv)

    runs = load_runs(args.results)
    print(f'results md5 {file_md5(args.results)}, '
          f'runner.py md5 {file_md5(os.path.abspath(runner.__file__))}, '
          f'seed {runner.BOOTSTRAP_SEED}, runs {len(runs)}\n')

    interval = f'{LEVEL:.0%} bootstrap interval'
    print(f'{"class":8s} {"ratio":>8s} {interval:>24s} {"ratio range":>20s}')
    for cls in runner.CLASS_OF[1:]:
        ratios = [times[cls] / times['base'] for times in runs]
        lo, hi = runner.boot_ci(ratios, level=LEVEL)
        print(f'{cls:8s} {statistics.median(ratios):8.3f} '
              f'{lo:11.3f} to {hi:<9.3f} '
              f'{min(ratios):9.3f} to {max(ratios):.3f}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
