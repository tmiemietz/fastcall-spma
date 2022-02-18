#!/usr/bin/env python3

"""This file generates a statistics CSV for the cycle counting benchmarks."""

from os import scandir
import csv
import re
import numpy as np

INPUT = "./results/"
INPUT_RE = re.compile("cycles-(.+)\.csv")
OUTPUT_FILE = "./cycle_stats.csv"
"""The resulting evaluation will be stored here."""

OUTPUT_HEADER = ["CPU", "mitigation", "kernel", "benchmark", "adjusted", "mean",
                 "median", "p1", "p25", "p50", "p75", "p99", "std", "iqr",
                 "min", "max"]
NOOP_COL = "noop"
"""
The median of this column will be used to remove the timing overhead for the
"adjusted" statistical measurements."""

OVERFLOW_THRESHOLD = 10**10
"""Ignore cycle counts larger than this.

Due to a previous bug in the benchmark script, the counter overflowed regularly.
Fortunately, these occurrences can be easily filtered and ignored.
"""


def main():
    """Read the benchmark results and write the output CSV."""
    results = read_cpus()
    with open(OUTPUT_FILE, "w") as f:
        writer = csv.writer(f)
        writer.writerow(OUTPUT_HEADER)
        writer.writerows(results)


def read_cpus():
    """Read data for each cpu.

    The resulting column format is ["CPU", ..., "max"].
    """
    results = []
    for entry in scandir(INPUT):
        if not entry.is_dir():
            continue

        results += [[entry.name] + r for r in read_mitigations(entry.path)]

    return results


def read_mitigations(path):
    """Read data for each mitigation.

    The resulting column format is ["mitigation", ..., "max"].
    """
    results = []
    for entry in scandir(path):
        if not entry.is_dir():
            continue

        results += [[entry.name] + r for r in read_kernels(entry.path)]

    return results


def read_kernels(path):
    """Read data for each kernel.

    The resulting column format is ["kernel", ..., "max"].
    """
    results = []
    for entry in scandir(path):
        if not entry.is_file():
            continue

        match = INPUT_RE.match(entry.name)
        if not match:
            continue

        results += [[match.group(1)] + r for r in read_csv(entry.path)]

    return results


def read_csv(path):
    """Read the data from the CSV file.

    The resulting column format is ["benchmark", "adjusted", ..., "max"].
    """
    with open(path) as f:
        reader = csv.reader(f)
        header = next(reader)
        values = [[] for _ in range(len(header))]

        for row in reader:
            for i, value in enumerate(row):
                value = int(value)
                if value > OVERFLOW_THRESHOLD:
                    continue

                values[i].append(value)

    values = [np.array(m) for m in values]
    noop_median = None
    results = []
    for name, measurements in zip(header, values):
        result = calc_stats(measurements)
        results.append([name, False] + result)

        if name == NOOP_COL:
            noop_median = result[1]

    if noop_median is not None:
        for name, measurements in zip(header, values):
            measurements = measurements - noop_median
            result = calc_stats(measurements)
            results.append([name, True] + result)

    return results


def calc_stats(measurements):
    """Calculate the statistical measures form the individual measurements.

    The resulting column format is ["mean", ..., "max"].
    """
    mean = np.mean(measurements)
    median = np.median(measurements)
    percentiles = np.percentile(measurements, (1, 25, 50, 75, 99))
    std = np.std(measurements)
    iqr = percentiles[3] - percentiles[1]
    minimum = np.min(measurements)
    maximum = np.max(measurements)

    return [mean, median, *percentiles, std, iqr, minimum, maximum]


if __name__ == "__main__":
    main()
