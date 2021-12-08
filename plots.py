#!/usr/bin/python3
"""Script generating plots from the benchmark results.

This script reads the CSV files in ./results/ and generates plots for them in
./plots/.
It requires the packages numpy and matplotlib.

Usage: ./plots.py
"""

from os import scandir, path, makedirs
import csv
import numpy as np
from matplotlib import pyplot as plt

RESULTS_DIR = "./results/"
PLOTS_DIR = "./plots/"
CSV_EXT = ".csv"
PLOT_EXT = ".pdf"

MITIGATIONS = {"mitigations=auto": "default mitigations",
               "nopti%mds_off": "no KPTI/MDS", "mitigations=off": "no mitigations"}
"""
Mapping from directory names of different mitigation settings to plot legends.
"""

METHODS = {"vdso": "vDSO", "fastcall": "fastcall",
           "syscall": "syscall", "ioctl": "ioctl"}
"""Mapping from file names of the tested methods to plot labels."""

SCENARIOS = {"Empty Function": {"fastcall_examples_noop", "ioctl_noop",
                                "syscall_sys_ni_syscall", "vdso_noop"}, "64-Byte Copy": {"array/64"}}
"""
Mapping from plot titles for the tested scenarios to sets of identifying
substrings in the name columns of the CSVs.
"""

SCENARIO_COLUMN = "name"
RESULT_COLUMN = "cpu_time"
BAR_WIDTH = 1
BAR_SPACE = 0.6
"""Space between groups of bars in the plots."""

Y_LABEL = "latency [ns]"
FONT = {"family": "Linux Libertine, LibertinusSerif, serif",
        "size": 14}
"""This mimics the font used in the paper."""

BAR_OFFSET = -(len(MITIGATIONS) - 1) * BAR_WIDTH / 2
BAR_GROUP = len(MITIGATIONS) * BAR_WIDTH + BAR_SPACE


def main():
    """This iterates through all tested CPUs and generates plots."""
    plt.rc("font", **FONT)

    with scandir(RESULTS_DIR) as it:
        for entry in it:
            if not entry.is_dir():
                continue

            process_cpu(entry.path)


def process_cpu(cpu_dir):
    """This reads and plots data for a single CPU."""
    results = read_cpu(cpu_dir)
    cpu_dir = path.join(PLOTS_DIR, path.basename(cpu_dir))
    makedirs(cpu_dir, exist_ok=True)
    plot_cpu(cpu_dir, results)


def read_cpu(cpu_dir):
    """Read results for the CPU into an array.

    The shape of the array is (MITIGATIONS, METHODS, SCENARIOS).
    """
    results = []
    for mitigation in MITIGATIONS:
        miti_dir = path.join(cpu_dir, mitigation)
        results.append(read_mitigation(miti_dir))
    return np.stack(results)


def plot_cpu(cpu_dir, results):
    """Plot the results for this CPU into the given directory."""
    for i, scenario in enumerate(SCENARIOS):
        plot_dir = path.join(cpu_dir, scenario + PLOT_EXT)
        plot_scenario(plot_dir, scenario, results[:, :, i])


def plot_scenario(plot_file, title, results):
    """Create a single plot for the chosen CPU and scenario.

    This is a grouped bar chart with latency against method and color codings
    for the mitigations.
    """
    fig, ax = plt.subplots()
    ax.set_title(title)
    ax.set_ylabel(Y_LABEL)

    x = np.arange(len(METHODS)) * BAR_GROUP
    for i, mitigation in enumerate(MITIGATIONS.values()):
        ax.bar(x + BAR_OFFSET + i * BAR_WIDTH,
               results[i, :], BAR_WIDTH, label=mitigation)

    ax.set_xticks(x)
    ax.set_xticklabels(METHODS.values())
    ax.legend()
    fig.tight_layout()
    fig.savefig(plot_file)


def read_mitigation(miti_dir):
    """Read results for the mitigation into an array."""
    results = []
    for method in METHODS:
        method_file = path.join(miti_dir, method) + CSV_EXT
        results.append(read_method(method_file))
    return np.stack(results)


def read_method(method_file):
    """Read results for this csv file into an array."""
    array = np.zeros(len(SCENARIOS))
    with open(method_file) as csv_file:
        reader = csv.reader(csv_file)
        header = next(reader)
        scen_col = header.index(SCENARIO_COLUMN)
        result_col = header.index(RESULT_COLUMN)
        for row in reader:
            label = row[scen_col]
            index = find_scenario(label)
            if index is None:
                continue
            array[find_scenario(label)] = float(row[result_col])
    return array


def find_scenario(label):
    """Findout the index into the SCENARIOS dictionary for this label or None."""
    for i, idents in enumerate(SCENARIOS.values()):
        for ident in idents:
            if ident in label:
                return i


if __name__ == "__main__":
    main()
