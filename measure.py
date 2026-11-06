#!/usr/bin/env python3
"""Timing kernels for the minimal class representatives.

Each case is timed as the median of REPS repetitions of N additions ``a + b``,
preceded by a warm-up of WARMUP additions. The cyclic garbage collector is
disabled while a repetition is being timed. loop_overhead() times an empty
loop of the same shape; the caller subtracts it.

runner.py imports this module unchanged and adds the campaign controls: core
pinning, run order and environment capture. Running this file directly prints
a single uncontrolled measurement, which is useful only as a quick check.
"""

import gc
import statistics
import sys
import time
from typing import Callable, NamedTuple

import probe_full
import probe_limited


class PyObj:
    """Class 6: state stored in the object, dispatch at Python level, no C."""

    __slots__ = ('value', 'mode')

    def __init__(self, value, mode=0):
        self.value = value
        self.mode = mode

    def __add__(self, other):
        if type(other) is not PyObj:
            return NotImplemented
        return PyObj(self.value + other.value, self.mode | other.mode)


class Case(NamedTuple):
    """A measured case. ``cls`` identifies the class in the results."""

    cls: str
    factory: Callable[[float], object]
    label: str
    signature: str


REPS = 7
N = 300_000
WARMUP = 20_000


def bench(make, label):
    """Time ``a + b`` for two values created by ``make``.

    Returns ``(label, median, min, max)`` of the time per addition in
    nanoseconds over REPS repetitions, loop overhead included.
    """
    a, b = make(1.5), make(2.5)
    for _ in range(WARMUP):  # warm up inline caches and branch predictors
        a + b
    times = []
    for _ in range(REPS):
        gc.collect()
        gc.disable()
        t0 = time.perf_counter_ns()
        for _ in range(N):
            a + b
        t1 = time.perf_counter_ns()
        gc.enable()
        times.append((t1 - t0) / N)
    return label, statistics.median(times), min(times), max(times)


def loop_overhead():
    """Return the median time per iteration of an empty loop, in nanoseconds.

    The loop has the same shape as the timed loop in bench().
    """
    times = []
    for _ in range(REPS):
        gc.collect()
        gc.disable()
        t0 = time.perf_counter_ns()
        for _ in range(N):
            pass
        t1 = time.perf_counter_ns()
        gc.enable()
        times.append((t1 - t0) / N)
    return statistics.median(times)


# The order of the cases defines the case indices used by the run design.
CASES = [
    Case('base', float, 'base: native float', '(0,0)'),
    Case('3', probe_full.InObj, 'class 3: in-object, slots, full API',
         '(1,1)'),
    Case('4', probe_limited.InObj, 'class 4: in-object, slots, limited API',
         '(1,1)'),
    Case('5', probe_full.TblObj, 'class 5: table, slots, full API', '(1,1)'),
    Case('6', PyObj, 'class 6: in-object, Python, no C', '(1,1)'),
    Case('7', probe_limited.TblObj, 'class 7: table, slots, limited API',
         '(1,1)'),
]


def main():
    print(f'Python {sys.version.split()[0]}, N={N:,}, repetitions={REPS}\n')
    overhead = loop_overhead()
    print(f'empty loop overhead: {overhead:.2f} ns/iteration\n')

    rows = []
    for case in CASES:
        label, med, lo, hi = bench(case.factory, case.label)
        rows.append((label, case.signature,
                     med - overhead, lo - overhead, hi - overhead))

    base = rows[0][2]
    print(f'{"case":40s} {"signature":9s} {"ns/op":>8s} '
          f'{"range":>13s} {"x base":>7s}')
    print('-' * 81)
    for label, sig, med, lo, hi in rows:
        print(f'{label:40s} {sig:9s} {med:8.1f} '
              f'{lo:6.1f}-{hi:<6.1f} {med / base:7.2f}')


if __name__ == '__main__':
    main()
