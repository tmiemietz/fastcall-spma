"""This file plots a mitigation comparison between CPUs."""

from os import path, makedirs
from matplotlib import pyplot as plt
import numpy as np
from .utils import *

PLOT_CPUS = {"Intel(R)_Core(TM)_i7-4790_CPU_@_3.60GHz": "i7-4790",
             "Intel(R)_Xeon(R)_Platinum_8375C_CPU_@_2.90GHz": "Xeon 8375C"}
"""List of CPUs to compare."""

PLOT_MITI = ["mitigations=auto", "mitigations=off"]
"""List of mitigations to show."""

NORM_METHOD = "fastcall"
"""Method to use for normalizing against."""

GRID_ENABLE = True
"""Show horizontal grid lines."""

BAR_WIDTH = 1
BAR_SPACE = 0.6
"""Space between groups of bars in the plots."""

Y_LABEL = "latency relative to fastcalls per CPU [%]"
LABELS = len(PLOT_CPUS) * len(PLOT_MITI)
BAR_OFFSET = -(LABELS - 1) * BAR_WIDTH / 2
BAR_GROUP = LABELS * BAR_WIDTH + BAR_SPACE
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
        mi = list(MITIGATIONS.keys()).index(PLOT_MITI[0])
        me = list(METHODS.keys()).index(NORM_METHOD)
        norm = cpu[mi, me]
        cpu = cpu / norm * 100
        cpus.append(cpu)
    cpus = np.stack(cpus)

    makedirs(RESULTS_DIR, exist_ok=True)
    for i, scenario in enumerate(SCENARIOS):
        plot_scenario(scenario, cpus[:, :, :, i])


def plot_scenario(title, results):
    fig, ax = plt.subplots()
    ax.set_prop_cycle(color=COLORS)
    ax.set_title(title)
    ax.set_ylabel(Y_LABEL)

    labels = []
    bars = []
    for c, cpu in enumerate(PLOT_CPUS.values()):
        for mitigation in PLOT_MITI:
            labels.append(f"{cpu} / {MITIGATIONS[mitigation]}")
            m = list(MITIGATIONS.keys()).index(mitigation)
            bars.append(results[c, m])

    x = np.arange(len(METHODS)) * BAR_GROUP
    for i, (ys, label) in enumerate(zip(bars, labels)):
        xs = x + BAR_OFFSET + i * BAR_WIDTH
        bar = ax.bar(xs, ys, BAR_WIDTH, label=label)

    ax.set_xticks(x)
    ax.set_xticklabels(METHODS.values())
    ax.set_axisbelow(True)
    ax.yaxis.grid(GRID_ENABLE)
    ax.legend()
    fig.tight_layout()

    plot_file = path.join(RESULTS_DIR, PREFIX + title + PLOT_EXT)
    fig.savefig(plot_file)
