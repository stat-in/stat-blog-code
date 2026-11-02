# Docker を使わずに R で回すときのパッケージ導入。
#   Rscript env/install-packages.R
# Docker と同じ日付のスナップショット（Posit Package Manager）から入れるので、版がそろう。
# 日付は env/Dockerfile の CRAN_SNAPSHOT と同じにすること。
snapshot <- "2026-10-28"

if(Sys.info()[["sysname"]] == "Linux") {
  # Ubuntu / Debian 向けのバイナリ。コード名（noble など）は /etc/os-release から読む。
  os_release <- readLines("/etc/os-release")
  codename <- sub("^VERSION_CODENAME=", "", grep("^VERSION_CODENAME=", os_release, value = TRUE))
  repo <- sprintf("https://p3m.dev/cran/__linux__/%s/%s", codename, snapshot)
}else {
  repo <- sprintf("https://p3m.dev/cran/%s", snapshot)  # Windows / macOS はバイナリが自動で選ばれる
}

pkgs <- trimws(sub("#.*", "", readLines("env/r-packages.txt")))
pkgs <- pkgs[nzchar(pkgs)]
install.packages(pkgs, repos = c(CRAN = repo))
missing <- setdiff(pkgs, rownames(installed.packages()))
if(length(missing)) stop("入らなかったパッケージ: ", paste(missing, collapse = ", "))
cat("R パッケージを入れました（スナップショット ", snapshot, "）\n", sep = "")
