from matplotlib import pyplot as plt
from . import percpu, cpucmp
from .utils import *


def main():
    """This iterates through all tested CPUs and generates plots."""
    plt.rc("font", **FONT)

    results = read_benchmarks()
    percpu.plot(results)
    cpucmp.plot(results)


if __name__ == "__main__":
    main()
