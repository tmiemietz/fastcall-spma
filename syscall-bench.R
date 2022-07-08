library(tidyverse)

RESULTS <- "results"
PLOTS <- "plots/syscall_bench"
EXT <- ".png"
ARCHS <- list(
  x86 = c(
    "Intel(R)_Core(TM)_i7-4790_CPU_@_3.60GHz",
    "Intel(R)_Xeon(R)_Platinum_8252C_CPU_@_3.80GHz"
  ),
  ARM = c("Neoverse-N1-t4g.micro")
)

evaluate <- function(path) {
  df <- read_csv(path, col_types = "d")
  df_means <- df %>% colMeans()
  df_norm <- df_means

  for (i in 2:length(df_means)) {
    df_norm[i] <- df_means[i] - df_means[i - 1] - df_means["overhead"]
  }

  return(df_norm)
}

plot_arch <- function(arch, cpus) {
  df <- data.frame()
  for (cpu in cpus) {
    cpu_dir <- file.path(RESULTS, cpu)
    for (csv in list.files(
      path = cpu_dir, pattern = "syscall-bench.csv", recursive = TRUE
    )) {
      path <- dirname(csv)
      miti <- basename(path)
      evaluation <- evaluate(file.path(cpu_dir, csv))
      tmp <- data.frame(
        cpu = cpu, miti = miti, step = names(evaluation),
        cycles = evaluation, row.names = NULL
      )
      tmp$miti <- factor(tmp$miti,
        levels = c("mitigations=off", "nopti%mds=off", "mitigations=auto")
      )
      tmp$step <- factor(tmp$step, levels = tmp$step)
      df <- rbind(df, tmp)
    }
  }

  plots <- file.path(PLOTS, arch)
  dir.create(plots, recursive = TRUE, showWarnings = FALSE)

  plot <- ggplot(df, aes(step, cycles, fill = miti)) +
    geom_bar(stat = "identity", show.legend = FALSE) +
    facet_grid(cpu ~ miti) +
    theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))
  ggsave(paste0("bar_per_miti", EXT), plot, path = plots)

  plot <- ggplot(df, aes(miti, cycles, fill = miti)) +
    geom_bar(stat = "identity") +
    facet_grid(cpu ~ step) +
    theme(
      axis.title.x = element_blank(), axis.text.x = element_blank(),
      axis.ticks.x = element_blank()
    )
  ggsave(paste0("bar_per_step", EXT), plot, path = plots)

  plot <- ggplot(df, aes(miti, cycles, fill = step)) +
    geom_bar(
      stat = "identity", position = position_stack(reverse = TRUE),
      color = "gray"
    ) +
    facet_grid(. ~ cpu) +
    guides(fill = guide_legend(reverse = TRUE))
  ggsave(paste0("stacked_bar", EXT), plot, path = plots)
}

for (arch in names(ARCHS)) {
  plot_arch(arch, ARCHS[[arch]])
}