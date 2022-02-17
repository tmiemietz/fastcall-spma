from os import scandir, path, environ
import csv
import numpy as np

RESULTS_DIR = "./results/"
PLOTS_DIR = "./plots/"
CSV_EXT = ".csv"
PLOT_EXT = environ.get("PLOT_EXT", ".png")
"""Change this to .pdf if you want to generate PDF plots."""

PLOTTED_CPUS = ("AMD_Ryzen_7_3700X_8-Core_Processor",
                "Intel(R)_Xeon(R)_Platinum_8375C_CPU_@_2.90GHz",
                "Intel(R)_Core(TM)_i7-4790_CPU_@_3.60GHz")

MITIGATIONS = {"mitigations=auto": "Default Mitigations",
               "nopti%mds=off": "No KPTI/MDS", "mitigations=off": "No Mitigations"}
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
BYTES_COLUMN = "bytes_per_second"
LATENCY_TO_SECONDS = 1e-9
"""Factor for converting from given latency to latency in seconds."""

COLORS = ("1b9e77", "d95f02", "7570b3", "e7298a")
FONT = {"family": ["Linux Libertine", "Libertinus Serif", "serif"],
        "size": 14}
"""This mimics the font used in the paper."""

FRAMEON = False
"""Should there be a boarder around legends?"""


class Results:
    def __init__(self, array, cpus):
        self.array = array
        self.cpus = cpus


def read_benchmarks():
    """Read benchmark results into a Results object.

    The shape of the array is (CPU, MITIGATIONS, METHODS, SCENARIOS, L/T).
    The CPU names are stored in cpus.
    """
    results = []
    cpus = []

    with scandir(RESULTS_DIR) as it:
        for entry in it:
            if not entry.is_dir():
                continue

            if not entry.name in PLOTTED_CPUS:
                continue

            results.append(read_cpu(entry.path))
            cpus.append(entry.name)
    return Results(np.stack(results), cpus)


def read_cpu(cpu_dir):
    """Read results for the CPU into an array.

    The shape of the array is (MITIGATIONS, METHODS, SCENARIOS, L/T).
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
