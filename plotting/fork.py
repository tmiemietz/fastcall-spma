"""This file generates plots for the fork benchmarks."""

import csv
from os import makedirs, path, scandir
import numpy as np
from matplotlib import pyplot as plt
from .utils import Results, RESULTS_DIR, PLOTS_DIR, PLOT_EXT, COLORS, PLOTTED_CPUS

MITIGATIONS = {"mitigations=auto": "default mitigations",
               "mitigations=off": "no mitigations"}
"""
Mapping from directory names of different mitigation settings to plot legends.
"""

MEASURES = ("fork-simple", "fork-fastcall")
"""Measures/benchmarks which should be read."""

KERNELS = {"fastcall": "misc-fastcall.csv", "stock": "misc-fccmp.csv"}
"""The different kernels with their result files."""

AVERAGE = np.median
"""Operation for taking an average."""

GRID_ENABLE = True
"""Show horizontal grid lines."""

STACK = (
    ("fastcall", "fork-fastcall", "With\nRegistrations"),
    ("fastcall", "fork-simple", "Without\nRegistrations"),
    ("stock", "fork-simple", "Vanilla Kernel"),
)
"""
(kernel, measure, label) tuples describing the sections of the stacked bar plot.
"""

FIGURE_SIZE = (6, 2.5)
PLOT_NAME = "Fork"
Y_LABEL = "Latency [µs]"
SCALING = 10 ** -3
BAR_WIDTH = 0.2


def process():
    results = read_misc()
    plot_misc(results)


def read_misc():
    """Read benchmark results into a Results object.

    The shape of the array is (CPU, MITIGATIONS, KERNELS, MEASURES).
    The CPU names are stored in cpus.
    """
    results = []
    cpus = []

    with scandir(RESULTS_DIR) as it:
        for entry in it:
            if not entry.is_dir():
                continue
            if entry.name not in PLOTTED_CPUS:
                continue

            array = read_cpu(entry.path)
            if array is None:
                continue

            results.append(array)
            cpus.append(entry.name)
    return Results(np.stack(results), cpus)


def read_cpu(cpu_dir):
    """Read results for the CPU into an array.

    The shape of the array is (MITIGATIONS, KERNELS, MEASURES).
    """
    results = []
    for mitigation in MITIGATIONS:
        miti_dir = path.join(cpu_dir, mitigation)
        array = read_mitigation(miti_dir)
        if array is None:
            return None

        results.append(array)
    return np.stack(results)


def read_mitigation(miti_dir):
    """Read results for the mitigation into an array.

    The shape of the array is (KERNELS, MEASURES).
    """
    results = []

    for kernel in KERNELS.values():
        data_file = path.join(miti_dir, kernel)
        array = read_kernel(data_file)
        if array is None:
            return None

        results.append(array)
    return np.stack(results)


def read_kernel(data_file):
    """Read results for the kernel into an array.

    The shape of the array is (MEASURES).
    """
    if not path.exists(data_file):
        return None

    results = []
    with open(data_file) as csv_file:
        reader = csv.reader(csv_file)
        header = next(reader)

        col_map = []
        for col in header:
            try:
                i = MEASURES.index(col)
            except ValueError:
                i = -1
            col_map.append(i)

        for row in reader:
            array = np.full(len(MEASURES), np.nan)
            for i, col in enumerate(row):
                if col_map[i] < 0:
                    continue
                array[col_map[i]] = float(col)
            results.append(array)
    results = np.stack(results)
    results = AVERAGE(results, 0) * SCALING

    return np.stack(results)


def plot_misc(results: Results):
    """Plot fork benchmarks for all CPUs."""

    for i, cpu in enumerate(results.cpus):
        cpu_dir = path.join(PLOTS_DIR, cpu)
        makedirs(cpu_dir, exist_ok=True)
        plot_cpu(cpu_dir, results.array[i])


def plot_cpu(cpu_dir, results):
    """Plot a fork diagram for the CPU."""

    fig, ax = plt.subplots(figsize=FIGURE_SIZE)
    ax.set_prop_cycle(color=COLORS)
    ax.set_ylabel(Y_LABEL)

    labels = []
    stack = []
    for kernel, measure, label in STACK:
        labels.append(label)
        kernel = list(KERNELS.keys()).index(kernel)
        measure = MEASURES.index(measure)
        stack.append(results[:, kernel, measure])

    for ys, label in zip(stack, labels):
        ax.bar(MITIGATIONS.values(), ys, BAR_WIDTH, label=label)

    ax.set_xlim((-0.5, len(MITIGATIONS) - 0.5))
    ax.set_axisbelow(True)
    ax.yaxis.grid(GRID_ENABLE)
    ax.legend(loc="center left", bbox_to_anchor=(1, 0.5))
    fig.tight_layout()

    plot_file = path.join(cpu_dir, PLOT_NAME + PLOT_EXT)
    fig.savefig(plot_file, bbox_inches="tight")
    plt.close()
