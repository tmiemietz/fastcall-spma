# Create scatter plots for the cycle-accurate fastcall measurements.
# This helps to find multimodal latency distributions.

library(tidyverse)

RESULTS <- "results"
PLOTS <- "plots"
EXT <- ".png"
# Plot for following CPUs
CPUS <- c(
  "Intel(R)_Xeon(R)_Platinum_8252C_CPU_@_3.80GHz",
  "Intel(R)_Xeon(R)_Platinum_8375C_CPU_@_2.90GHz",
  "Intel(R)_Core(TM)_i7-4790_CPU_@_3.60GHz",
  "AMD_Ryzen_7_3700X_8-Core_Processor",
  "Neoverse-N1"
)

evaluate <- function(path) {
  read_csv(path, col_types = "d") %>%
    # subtract the benchmark overhead
    mutate(cycles = fastcall - median(noop), id = row_number()) %>%
    select(-fastcall, -noop) %>%
    filter(cycles <= quantile(cycles, 0.99))
}

for (cpu in CPUS) {
  cpu_dir <- file.path(RESULTS, cpu)
  df <- data.frame()
  for (csv in list.files(
    path = cpu_dir, pattern = "cycles-fastcall.csv", recursive = TRUE
  )) {
    dir <- dirname(csv)
    miti <- basename(dir)
    path <- file.path(cpu_dir, csv)
    tmp <- data.frame(miti = miti, evaluate(path))
    # fix the order of the mitigations
    tmp$miti <- factor(tmp$miti,
      levels = c("mitigations=off", "nopti%mds=off", "mitigations=auto")
    )
    df <- rbind(df, tmp)
  }

  plot <- ggplot(df, aes(x = id, y = cycles)) +
    facet_grid(. ~ miti) +
    # use a jitter plot to disperse the data points for better visibility
    geom_point(size = 0.1) +
    scale_x_continuous(name = "Iteration Number") +
    scale_y_continuous(name = "Cycles (<=99% Quantile)") +
    expand_limits(y = 0) +
    ggtitle(paste("Fastcall Latency of", cpu))

  plots <- file.path(PLOTS, cpu)
  dir.create(plots, recursive = TRUE, showWarnings = FALSE)
  ggsave(paste0("fastcall-cycles", EXT), plot, path = plots)
}