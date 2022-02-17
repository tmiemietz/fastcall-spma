"""This file plots a mitigation comparison between CPUs."""

from os import path, makedirs
from matplotlib import pyplot as plt
import numpy as np
from .utils import *

PLOT_CPUS = {"Intel(R)_Core(TM)_i7-4790_CPU_@_3.60GHz": "Intel Core i7-4790",
             "Intel(R)_Xeon(R)_Platinum_8375C_CPU_@_2.90GHz": "Intel Xeon 8375C"}
"""List of CPUs to compare."""

PLOT_MITI = ("mitigations=auto", "mitigations=off")
"""List of mitigations to show."""

NORM_METHOD = "fastcall"
"""Method to use for normalizing against."""

GRID_ENABLE = True
"""Show horizontal grid lines."""

BAR_WIDTH = 1
BAR_SPACE = 0.6
"""Space between groups of bars in the plots."""

FIGURE_HEIGHT = 3
TITLE_FONT = {"fontsize": 14}
Y_LABEL = "Latency [ns]"
LABELS = len(PLOT_MITI)
BAR_OFFSET = -(LABELS - 1) * BAR_WIDTH / 2
BAR_GROUP = LABELS * BAR_WIDTH + BAR_SPACE
PADDING_TOP = 0.05
PREFIX = "CPU-compare "
"""Prefix for the plot files."""


def plot(results: Results):
    """Plots a mitigation comparison between CPUs.

    This uses the latency values which are normalized relative to the latency of
    the first mitigation for each CPU.
    """
    cpus = []
    for cpu in PLOT_CPUS:
        cpu = results.array[results.cpus.index(cpu), :, :, :, 0]
        cpus.append(cpu)
    cpus = np.stack(cpus)

    makedirs(RESULTS_DIR, exist_ok=True)
    for i, scenario in enumerate(SCENARIOS):
        plot_scenario(scenario, cpus[:, :, :, i])


def plot_scenario(title, results):
    method = list(METHODS.keys()).index(NORM_METHOD)
    mitigation = list(MITIGATIONS.keys()).index(PLOT_MITI[0])
    fastcalls = results[:, (mitigation,)][:, :, (method,)]
    relative = results / fastcalls * (1 + PADDING_TOP)
    y_max = (fastcalls * np.amax(relative)).flatten()

    fig, axes = plt.subplots(ncols=len(PLOT_CPUS))

    for i, (ax, cpu) in enumerate(zip(axes, PLOT_CPUS.values())):
        plot_cpu(ax, cpu, results[i], y_max[i], i == 0)

    fig.legend(ncol=len(PLOT_MITI), loc="lower center",
               bbox_to_anchor=(0.5, 0.95))
    fig.set_figheight(FIGURE_HEIGHT)
    fig.tight_layout()

    fname = PREFIX + title + PLOT_EXT
    fname = fname.replace(" ", "-")
    plot_file = path.join(PLOTS_DIR, fname)
    fig.savefig(plot_file, bbox_inches="tight")


def plot_cpu(ax, cpu, results, y_max, first):
    """Plot the results for a single CPU into a subplot."""

    ax.set_prop_cycle(color=COLORS)
    ax.set_title(cpu, TITLE_FONT)
    if first:
        ax.set_ylabel(Y_LABEL)

    labels = []
    bars = []
    for mitigation in PLOT_MITI:
        labels.append(MITIGATIONS[mitigation])
        m = list(MITIGATIONS.keys()).index(mitigation)
        bars.append(results[m])

    x = np.arange(len(METHODS)) * BAR_GROUP
    for i, (ys, label) in enumerate(zip(bars, labels)):
        if not first:
            label = None

        xs = x + BAR_OFFSET + i * BAR_WIDTH
        ax.bar(xs, ys, BAR_WIDTH, label=label)

    ax.set_xticks(x)
    ax.set_xticklabels(METHODS.values())
    ax.set_ylim(top=y_max)
    ax.set_axisbelow(True)
    ax.yaxis.grid(GRID_ENABLE)
