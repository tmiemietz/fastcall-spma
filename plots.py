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
PLOT_EXT = ".png"

MITIGATIONS = {"mitigations=auto": "default mitigations",
               "nopti%mds=off": "no KPTI/MDS", "mitigations=off": "no mitigations"}
"""
Mapping from directory names of different mitigation settings to plot legends.
"""

METHODS = {"vdso": "vDSO", "fastcall": "fastcall",
           "syscall": "syscall", "ioctl": "ioctl"}
"""Mapping from file names of the tested methods to plot labels."""

GRID_ENABLE = True
"""Show horizontal grid lines."""

BAR_LABELS = False
"""Add labels to the bars showing the y value."""

ARROW_ENABLE = True
"""Draw an arrow indicating relative improvement."""

ARROW_METHODS = ("fastcall", "syscall")
"""Draw an arrow between these methods to show an improvement factor."""

ARROW_IDS = tuple(list(METHODS.keys()).index(m) for m in ARROW_METHODS)

ARROW_MITIGATION = list(MITIGATIONS.keys()).index("mitigations=auto")
"""Draw the improvement arrow for this mitigation."""

ARROW_COLOR = "0.4"

SCENARIOS = {"Empty Function": {"fastcall_examples_noop", "ioctl_noop",
                                "syscall_sys_ni_syscall", "vdso_noop"}, "64-Byte Copy": {"array/64"}}
"""
Mapping from plot titles for the tested scenarios to sets of identifying
substrings in the name columns of the CSVs.
"""

SCENARIO_COLUMN = "name"
RESULT_COLUMN = "cpu_time"
BYTES_COLUMN = "bytes_per_second"
BAR_WIDTH = 1
BAR_SPACE = 0.6
"""Space between groups of bars in the plots."""

Y_LABEL_LATENCY = "latency [ns]"
Y_LABEL_THROUGHPUT_INVOCATIONS = "invocations per second"
Y_LABEL_THROUGHPUT_BYTES = "bytes per second"
LATENCY_TO_SECONDS = 1e-9
"""Factor for converting from given latency to latency in seconds."""

FONT = {"family": ["Linux Libertine", "Libertinus Serif", "serif"],
        "size": 14}
"""This mimics the font used in the paper."""

COLORS = ("1b9e77", "d95f02", "7570b3")
BAR_OFFSET = -(len(MITIGATIONS) - 1) * BAR_WIDTH / 2
BAR_GROUP = len(MITIGATIONS) * BAR_WIDTH + BAR_SPACE

EVALUATIONS = {}


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


def read_mitigation(miti_dir):
    """Read results for the mitigation into an array."""
    results = []
    for method in METHODS:
        method_file = path.join(miti_dir, method) + CSV_EXT
        results.append(read_method(method_file))
    return np.stack(results)


def read_method(method_file):
    """Read results for this csv file into an array.

    The array has two columns: one for latency and one for throughput (bytes).
    """
    array = np.zeros((len(SCENARIOS), 2))
    with open(method_file) as csv_file:
        reader = csv.reader(csv_file)
        header = next(reader)
        scen_col = header.index(SCENARIO_COLUMN)
        result_col = header.index(RESULT_COLUMN)
        bytes_col = header.index(BYTES_COLUMN)
        for row in reader:
            label = row[scen_col]
            index = find_scenario(label)
            if index is None:
                continue
            array[index, 0] = float(row[result_col])
            throughput = row[bytes_col]
            array[index, 1] = np.nan if throughput == "" else float(throughput)
    return array


def find_scenario(label):
    """Findout the index into the SCENARIOS dictionary for this label or None."""
    for i, idents in enumerate(SCENARIOS.values()):
        for ident in idents:
            if ident in label:
                return i


def plot_cpu(cpu_dir, results):
    """Plot the evaluations for this CPU into the given directory."""
    for evaluation, fn in EVALUATIONS.items():
        eval_dir = path.join(cpu_dir, evaluation)
        plot_evaluation(eval_dir, fn, results)


def plot_evaluation(eval_dir, function, results):
    """Plot the results for this evaluation into the given directory."""
    for i, scenario in enumerate(SCENARIOS):
        makedirs(eval_dir, exist_ok=True)
        plot_file = path.join(eval_dir, scenario.replace(" ", "_") + PLOT_EXT)
        function(plot_file, scenario, results[:, :, i])


def plot_latency(plot_file, title, results):
    """Create a single plot depicting latency."""
    plot_scenario(plot_file, title, Y_LABEL_LATENCY, results[:, :, 0])


EVALUATIONS["latency"] = plot_latency


def plot_throughput_invocations(plot_file, title, results):
    """Create a single plot depicting invocation per time."""
    results = 1 / (LATENCY_TO_SECONDS * results[:, :, 0])
    plot_scenario(plot_file, title, Y_LABEL_THROUGHPUT_INVOCATIONS, results)


EVALUATIONS["throughput_invocations"] = plot_throughput_invocations


def plot_throughput_bytes(plot_file, title, results):
    """Create a single plot depicting bytes per second."""
    plot_scenario(plot_file, title, Y_LABEL_THROUGHPUT_BYTES, results[:, :, 1])


EVALUATIONS["throughput_bytes"] = plot_throughput_bytes


def plot_scenario(plot_file, title, y_label, results):
    """Create a single plot for the chosen CPU and scenario.

    This is a grouped bar chart which plots against method and uses color
    codings for the mitigations.
    """
    if np.any(np.isnan(results)):
        return

    fig, ax = plt.subplots()
    ax.set_prop_cycle(color=COLORS)
    ax.set_title(title)
    ax.set_ylabel(y_label)

    x = np.arange(len(METHODS)) * BAR_GROUP
    for i, mitigation in enumerate(MITIGATIONS.values()):
        xs = x + BAR_OFFSET + i * BAR_WIDTH
        ys = results[i]
        bar = ax.bar(xs, ys, BAR_WIDTH, label=mitigation)
        if BAR_LABELS:
            bar = ax.bar_label(bar, fmt="%.2e", rotation="vertical", padding=4)

    if ARROW_ENABLE:
        draw_arrow(ax, x, results)

    ax.set_xticks(x)
    ax.set_xticklabels(METHODS.values())
    ax.set_axisbelow(True)
    ax.yaxis.grid(GRID_ENABLE)
    ax.legend()
    fig.tight_layout()
    fig.savefig(plot_file)


def draw_arrow(ax, x, results):
    """Draw an arrow between two methods indicating relative improvement."""
    arrow_ids = list(ARROW_IDS)
    arrow_ys = list(results[ARROW_MITIGATION, arrow_id]
                    for arrow_id in arrow_ids)
    horizontalalignment = "right"
    if arrow_ys[0] > arrow_ys[1]:
        arrow_ys.reverse()
        arrow_ids.reverse()
        horizontalalignment = "left"

    arrow_x = x[arrow_ids[0]] + BAR_OFFSET + ARROW_MITIGATION * BAR_WIDTH
    arrow_coords = np.stack(list(np.array((arrow_x, arrow_y))
                            for arrow_y in arrow_ys))
    ax.annotate("", *arrow_coords,
                arrowprops=dict(arrowstyle="|-|", color=ARROW_COLOR))

    center_coords = np.average(arrow_coords, axis=0)
    percent = round((arrow_ys[1] / arrow_ys[0] - 1) * 100)
    text = f"+{percent}%"
    bbox = dict(boxstyle="round", color="w", ec="0.7", alpha=0.7)
    ax.annotate(text, center_coords, color=ARROW_COLOR,
                bbox=bbox)


if __name__ == "__main__":
    main()
