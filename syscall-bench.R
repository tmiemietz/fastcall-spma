library(tidyverse)

PLOTS <- "plots/syscall_bench"

evaluate <- function(path) {
  df <- read_csv(path, col_types = "d")
  df_means <- df %>% colMeans()
  df_norm <- df_means

  for (i in 2:length(df_means)) {
    df_norm[i] <- df_means[i] - df_means[i - 1] - df_means["overhead"]
  }

  return(df_norm)
}

df <- data.frame()
for (csv in list.files(pattern = "syscall-bench.csv", recursive = TRUE)) {
  path <- dirname(csv)
  miti <- basename(path)
  cpu <- basename(dirname(path))
  evaluation <- evaluate(csv)
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

dir.create(PLOTS, recursive = TRUE, showWarnings = FALSE)

plot <- ggplot(df, aes(step, cycles, fill = miti)) +
  geom_bar(stat = "identity", show.legend = FALSE) +
  facet_grid(cpu ~ miti) +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))
ggsave("bar_per_miti.png", plot, path = PLOTS)

plot <- ggplot(df, aes(miti, cycles, fill = miti)) +
  geom_bar(stat = "identity") +
  facet_grid(cpu ~ step) +
  theme(
    axis.title.x = element_blank(), axis.text.x = element_blank(),
    axis.ticks.x = element_blank()
  )
ggsave("bar_per_step.png", plot, path = PLOTS)

plot <- ggplot(df, aes(miti, cycles, fill = step)) +
  geom_bar(
    stat = "identity", position = position_stack(reverse = TRUE),
    color = "gray"
  ) +
  facet_grid(. ~ cpu) +
  guides(fill = guide_legend(reverse = TRUE))
ggsave("stacked_bar.png", plot, path = PLOTS)