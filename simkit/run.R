# シミュレーションの実行入口
#
#   Rscript simkit/run.R posts/<slug> [--pilot] [--cores N] [--fresh] [--allow-dirty]
#
# 通常は Makefile（make sim）から呼ぶ。リポジトリのルートで実行すること。

args <- commandArgs(trailingOnly = TRUE)
if(length(args) < 1) stop("使い方: Rscript simkit/run.R posts/<slug> [--pilot] [--cores N]")

flag <- function(name) {
  return(name %in% args)
}
value <- function(name, default) {
  i <- match(name, args)
  if(is.na(i) || i == length(args)) return(default)
  return(args[[i + 1]])
}

file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
here <- dirname(normalizePath(sub("^--file=", "", file_arg)))
options(simkit.path = file.path(here, "simkit.R"))
source(file.path(here, "simkit.R"))

run_sim(
  normalizePath(args[[1]], mustWork = TRUE),
  pilot = flag("--pilot"),
  cores = as.integer(value("--cores", "1")),
  fresh = flag("--fresh"),
  allow_dirty = flag("--allow-dirty")
)
