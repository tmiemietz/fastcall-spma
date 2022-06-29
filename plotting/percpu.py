"""This file plots per-CPU benchmark results."""

from os import makedirs, path
from matplotlib import pyplot as plt
import numpy as np
from .utils import *

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

BAR_WIDTH = 1
BAR_SPACE = 0.6
"""Space between groups of bars in the plots."""

Y_LABEL_LATENCY = "Latency [ns]"
Y_LABEL_THROUGHPUT_INVOCATIONS = "Invocations per Second"
Y_LABEL_THROUGHPUT_BYTES = "Bytes per Second"

BAR_OFFSET = -(len(MITIGATIONS) - 1) * BAR_WIDTH / 2
BAR_GROUP = len(MITIGATIONS) * BAR_WIDTH + BAR_SPACE

EVALUATIONS = {}


def plot(results: Results):
    """This plots the data for every CPU."""
    for i, cpu in enumerate(results.cpus):
        cpu_dir = path.join(PLOTS_DIR, cpu)
        plot_cpu(cpu_dir, results.array[i])


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
        function(plot_file, results[:, :, i])


def plot_latency(plot_file, results):
    """Create a single plot depicting latency."""
    plot_scenario(plot_file, Y_LABEL_LATENCY, results[:, :, 0])


EVALUATIONS["latency"] = plot_latency


def plot_throughput_invocations(plot_file, results):
    """Create a single plot depicting invocation per time."""
    results = 1 / (LATENCY_TO_SECONDS * results[:, :, 0])
    plot_scenario(plot_file, Y_LABEL_THROUGHPUT_INVOCATIONS, results)


EVALUATIONS["throughput_invocations"] = plot_throughput_invocations


def plot_throughput_bytes(plot_file, results):
    """Create a single plot depicting bytes per second."""
    plot_scenario(plot_file, Y_LABEL_THROUGHPUT_BYTES, results[:, :, 1])


EVALUATIONS["throughput_bytes"] = plot_throughput_bytes


def plot_scenario(plot_file, y_label, results):
    """Create a single plot for the chosen CPU and scenario.

    This is a grouped bar chart which plots against method and uses color
    codings for the mitigations.
    """
    if np.any(np.isnan(results)):
        return

    fig, ax = plt.subplots()
    ax.set_prop_cycle(color=COLORS)
    ax.set_ylabel(y_label)

    x = np.arange(len(METHODS)) * BAR_GROUP
    for i, mitigation in enumerate(MITIGATIONS.values()):
        xs = x + BAR_OFFSET + i * BAR_WIDTH
        ys = results[i]
        bar = ax.bar(xs, ys, BAR_WIDTH, label=mitigation)
        if BAR_LABELS:
            ax.bar_label(bar, fmt="%.2e", rotation="vertical", padding=4)

    if ARROW_ENABLE:
        draw_arrow(ax, x, results)

    ax.set_xticks(x)
    ax.set_xticklabels(METHODS.values())
    ax.set_axisbelow(True)
    ax.yaxis.grid(GRID_ENABLE)
    ax.legend(ncol=len(MITIGATIONS), loc="lower center",
              bbox_to_anchor=(0.5, 1.05))
    fig.tight_layout()
    fig.savefig(plot_file, bbox_inches="tight")
    plt.close()


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
