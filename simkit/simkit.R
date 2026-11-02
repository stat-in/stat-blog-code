# simkit.R: シミュレーション実行の共通部品
#
# 各テーマの posts/<slug>/model.R が generate() / analyse() / summarise() を定義し、
# ここの run_sim() が条件 × 反復の実行、乱数の割り当て、途中保存と再開、要約、
# 実行記録（run_info.json）を受け持つ。

suppressPackageStartupMessages({
  library(yaml)
  library(jsonlite)
})

SIMKIT_VERSION <- "0.1.0"

# ---- 設定と条件表 --------------------------------------------------------

# YAML 1.1 では n / y / yes / no / on / off が真偽値になってしまう（変数名 n が FALSE になる）。
# true / false だけを真偽値として扱い、それ以外は文字列のまま読む。
yaml_bool <- function(x) {
  if(tolower(x) %in% c("true", "false")) return(tolower(x) == "true")
  return(x)
}

read_config <- function(sim_dir) {
  cfg <- yaml::read_yaml(file.path(sim_dir, "config.yaml"),
                         handlers = list("bool#yes" = yaml_bool, "bool#no" = yaml_bool))
  for(key in c("slug", "seed", "reps", "pilot_reps", "design")) {
    if(is.null(cfg[[key]])) stop("config.yaml に ", key, " がありません")
  }
  return(cfg)
}

# 条件表を作る。最初の変数が最も速く変わる（expand.grid と同じ順）。
make_design <- function(design) {
  grid <- expand.grid(design, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  return(cbind(cond_id = seq_len(nrow(grid)), grid))
}

# ---- 乱数 ----------------------------------------------------------------

# 条件 cond_id の反復 1..reps に、それぞれ独立な L'Ecuyer-CMRG の乱数列を割り当てる。
# 条件ごとに stream、反復ごとに substream を使うので、並列数や実行順に依存しない。
rep_seeds <- function(seed, cond_id, reps) {
  RNGkind("L'Ecuyer-CMRG", "Inversion", "Rejection")
  set.seed(seed)
  s <- get(".Random.seed", envir = globalenv())
  for(i in seq_len(cond_id)) s <- parallel::nextRNGStream(s)
  out <- vector("list", reps)
  for(r in seq_len(reps)) {
    s <- parallel::nextRNGSubStream(s)
    out[[r]] <- s
  }
  return(out)
}

# ---- 1条件の実行 ---------------------------------------------------------

run_one <- function(r, cond, seeds, model) {
  assign(".Random.seed", seeds[[r]], envir = globalenv())
  res <- tryCatch({
    dat <- model$generate(cond)
    value <- unlist(model$analyse(dat, cond))
    if(!(is.numeric(value) || is.logical(value)) || is.null(names(value))) {
      stop("analyse() は名前付きの数値（またはリスト）を返してください")
    }
    list(rep = r, ok = TRUE, value = value)
  }, error = function(e) list(rep = r, ok = FALSE, error = conditionMessage(e)))
  return(res)
}

# 重い計算（1反復が長い）では反復ごとに子プロセスへ配り、空いたコアから次を取る。
par_lapply <- function(X, FUN, cores, heavy = FALSE) {
  if(cores > 1 && .Platform$OS.type != "windows") {
    res <- parallel::mclapply(X, FUN, mc.cores = cores, mc.preschedule = !heavy)
  }else {
    res <- lapply(X, FUN)
  }
  return(res)
}

# 条件 cond_id の反復 rep_ids を回す。乱数は反復番号で決まるので、どう分けて回しても同じ結果になる。
run_condition <- function(cond, cond_id, seed, rep_ids, model, cores, heavy = FALSE) {
  seeds <- rep_seeds(seed, cond_id, max(rep_ids))
  started <- Sys.time()
  outs <- par_lapply(rep_ids, function(r) run_one(r, cond, seeds, model), cores, heavy)
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))

  ok <- vapply(outs, function(o) isTRUE(o$ok), logical(1))
  if(any(ok)) {
    mat <- do.call(rbind, lapply(outs[ok], `[[`, "value"))
    results <- data.frame(rep = vapply(outs[ok], `[[`, integer(1), "rep"), mat,
                          check.names = FALSE)
  }else {
    results <- data.frame(rep = integer(0))
  }
  errors <- data.frame(
    rep = vapply(outs[!ok], function(o) as.integer(o$rep), integer(1)),
    error = vapply(outs[!ok], function(o) as.character(o$error), character(1))
  )
  return(list(results = results, errors = errors, elapsed = elapsed))
}

# 途中保存したブロックを1条件分にまとめる。
combine_blocks <- function(blocks) {
  filled <- Filter(function(b) nrow(b$results) > 0, blocks)
  if(length(filled)) {
    results <- do.call(rbind, lapply(filled, `[[`, "results"))
  }else {
    results <- data.frame(rep = integer(0))
  }
  errors <- do.call(rbind, lapply(blocks, `[[`, "errors"))
  elapsed <- sum(vapply(blocks, `[[`, numeric(1), "elapsed"))
  return(list(results = results, errors = errors, elapsed = elapsed))
}

# ---- 性能指標（Morris, White & Crowther, 2019 の MCSE） ------------------

# est: 反復ごとの推定値, truth: 真値。返り値は推定値・MCSE・計算に使えた反復数。
perf_bias <- function(est, truth) {
  est <- est[is.finite(est)]; n <- length(est)
  return(c(estimate = mean(est) - truth, mcse = sd(est) / sqrt(n), n = n))
}

perf_empse <- function(est) {
  est <- est[is.finite(est)]; n <- length(est)
  s <- sd(est)
  return(c(estimate = s, mcse = s / sqrt(2 * (n - 1)), n = n))
}

perf_mse <- function(est, truth) {
  e2 <- (est[is.finite(est)] - truth)^2; n <- length(e2)
  m <- mean(e2)
  return(c(estimate = m, mcse = sqrt(sum((e2 - m)^2) / (n * (n - 1))), n = n))
}

perf_rmse <- function(est, truth) {
  m <- perf_mse(est, truth)
  r <- sqrt(m[["estimate"]])
  return(c(estimate = r, mcse = m[["mcse"]] / (2 * r), n = m[["n"]]))
}

# 割合（棄却率・被覆率など）。x は論理値か 0/1。
perf_rate <- function(x) {
  x <- as.numeric(x[!is.na(x)]); n <- length(x)
  p <- mean(x)
  return(c(estimate = p, mcse = sqrt(p * (1 - p) / n), n = n))
}

# lo, hi: 区間の下限と上限
perf_coverage <- function(lo, hi, truth) {
  return(perf_rate(lo <= truth & truth <= hi))
}

perf_row <- function(method, measure, p) {
  return(data.frame(method = method, measure = measure,
                    estimate = p[["estimate"]], mcse = p[["mcse"]], n_valid = as.integer(p[["n"]])))
}

# ---- 実行記録 ------------------------------------------------------------

git_info <- function(paths) {
  commit <- tryCatch(system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE),
                     error = function(e) NA_character_, warning = function(w) NA_character_)
  status <- tryCatch(system2("git", c("status", "--porcelain", "--", paths),
                             stdout = TRUE, stderr = FALSE),
                     error = function(e) character(0), warning = function(w) character(0))
  return(list(commit = if(length(commit)) commit[[1]] else NA_character_,
              dirty = length(status) > 0, dirty_files = status))
}

cpu_model <- function() {
  if(file.exists("/proc/cpuinfo")) {
    line <- grep("^model name", readLines("/proc/cpuinfo", warn = FALSE), value = TRUE)
    if(length(line)) return(trimws(sub(".*:", "", line[[1]])))
  }
  out <- tryCatch(system2("sysctl", c("-n", "machdep.cpu.brand_string"), stdout = TRUE, stderr = FALSE),
                  error = function(e) character(0), warning = function(w) character(0))
  if(length(out)) return(out[[1]])
  return(NA_character_)
}

package_versions <- function() {
  pkgs <- sort(setdiff(loadedNamespaces(), rownames(installed.packages(priority = "base"))))
  return(as.list(vapply(pkgs, function(p) as.character(utils::packageVersion(p)), character(1))))
}

fingerprint <- function(cfg, reps, files) {
  return(list(seed = cfg$seed, reps = reps, design = cfg$design,
              files = as.list(unname(tools::md5sum(files)))))
}

# ---- 本体 ----------------------------------------------------------------

run_sim <- function(sim_dir, pilot = FALSE, cores = 1L, fresh = FALSE, allow_dirty = FALSE,
                    simkit_file = getOption("simkit.path", "simkit/simkit.R")) {
  cfg <- read_config(sim_dir)
  RNGkind("L'Ecuyer-CMRG", "Inversion", "Rejection")
  mode <- if(pilot) "pilot" else "full"
  reps <- as.integer(if(pilot) cfg$pilot_reps else cfg$reps)
  design <- make_design(cfg$design)
  # checkpoint_every を書くと「重い計算」として扱い、その反復数ごとに途中保存する
  heavy <- !is.null(cfg$checkpoint_every)
  block_size <- if(heavy) as.integer(cfg$checkpoint_every) else reps
  blocks <- split(seq_len(reps), ceiling(seq_len(reps) / block_size))

  model_file <- file.path(sim_dir, "model.R")
  model <- new.env()
  sys.source(model_file, envir = model)
  for(fn in c("generate", "analyse", "summarise")) {
    if(!exists(fn, envir = model, inherits = FALSE)) stop("model.R に ", fn, "() がありません")
  }

  git <- git_info(c(model_file, file.path(sim_dir, "config.yaml"), dirname(simkit_file)))
  if(!pilot && git$dirty && !allow_dirty) {
    stop("コードに未コミットの変更があります。本番はコミット済みのコードで回してください",
         "（どうしても必要なら --allow-dirty）:\n", paste(git$dirty_files, collapse = "\n"))
  }

  res_dir <- file.path(sim_dir, "results", mode)
  if(fresh && dir.exists(res_dir)) unlink(res_dir, recursive = TRUE)
  dir.create(res_dir, recursive = TRUE, showWarnings = FALSE)
  # 途中結果を再利用してよいかの判定用。設定かコードが変わったら作り直しを求める。
  fp <- as.character(jsonlite::toJSON(fingerprint(cfg, reps, c(model_file, simkit_file)),
                                      auto_unbox = TRUE, pretty = TRUE))
  fp_file <- file.path(res_dir, "fingerprint.json")
  if(file.exists(fp_file) && !identical(paste(readLines(fp_file), collapse = "\n"), fp)) {
    stop("前回の途中結果と設定かコードが違います。--fresh で作り直してください")
  }
  writeLines(fp, fp_file)

  started <- Sys.time()
  cat(sprintf("[%s] %s: %d 条件 × %d 反復, %d コア%s\n", mode, cfg$slug, nrow(design), reps, cores,
              if(heavy) sprintf("（%d 反復ごとに途中保存）", block_size) else ""))
  raw <- vector("list", nrow(design))
  for(i in seq_len(nrow(design))) {
    cond <- as.list(design[i, -1, drop = FALSE])
    label <- paste(names(cond), unlist(cond), sep = "=", collapse = ", ")
    cond_dir <- file.path(res_dir, sprintf("cond-%04d", i))
    dir.create(cond_dir, showWarnings = FALSE)
    done <- vector("list", length(blocks))
    for(b in seq_along(blocks)) {
      file <- file.path(cond_dir, sprintf("block-%04d.rds", b))
      if(file.exists(file)) {
        done[[b]] <- readRDS(file)
        next
      }
      done[[b]] <- run_condition(cond, i, cfg$seed, blocks[[b]], model, cores, heavy)
      saveRDS(done[[b]], file)
      if(length(blocks) > 1) {
        cat(sprintf("  [%d/%d] %s: 反復 %d/%d まで %.1f 秒\n", i, nrow(design), label,
                    max(blocks[[b]]), reps, done[[b]]$elapsed))
      }
    }
    raw[[i]] <- combine_blocks(done)
    cat(sprintf("  [%d/%d] %s: 計 %.1f 秒, 失敗 %d\n", i, nrow(design), label,
                raw[[i]]$elapsed, nrow(raw[[i]]$errors)))
  }

  summary <- do.call(rbind, lapply(seq_len(nrow(design)), function(i) {
    cond <- as.list(design[i, -1, drop = FALSE])
    s <- model$summarise(raw[[i]]$results, cond)
    cbind(design[rep(i, nrow(s)), , drop = FALSE], s, n_failed = nrow(raw[[i]]$errors))
  }))
  rownames(summary) <- NULL
  finished <- Sys.time()

  out_dir <- if(pilot) res_dir else file.path(sim_dir, "outputs")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(summary, file.path(out_dir, "summary.csv"), row.names = FALSE, fileEncoding = "UTF-8")

  compute_sec <- sum(vapply(raw, `[[`, numeric(1), "elapsed"))
  info <- list(
    slug = cfg$slug, mode = mode, seed = cfg$seed, reps = reps,
    n_conditions = nrow(design), cores = cores,
    n_failed = sum(vapply(raw, function(x) nrow(x$errors), integer(1))),
    started_at = format(started, "%Y-%m-%dT%H:%M:%S%z"),
    finished_at = format(finished, "%Y-%m-%dT%H:%M:%S%z"),
    compute_sec = round(compute_sec, 1),
    git = git[c("commit", "dirty")],
    platform = list(os = paste(Sys.info()[["sysname"]], Sys.info()[["release"]]),
                    cpu = cpu_model(), image = Sys.getenv("SIM_IMAGE", NA_character_)),
    language = list(name = "R", version = R.version.string,
                    rng = "L'Ecuyer-CMRG（条件ごとに stream、反復ごとに substream）"),
    simkit = SIMKIT_VERSION,
    packages = package_versions()
  )
  jsonlite::write_json(info, file.path(out_dir, "run_info.json"), auto_unbox = TRUE,
                       pretty = TRUE, na = "null")

  cat(sprintf("完了: 計算 %.1f 秒, 失敗 %d 件 -> %s\n", compute_sec, info$n_failed, out_dir))
  if(pilot) {
    full_min <- compute_sec * as.numeric(cfg$reps) / reps / 60
    cat(sprintf("本番（%d 反復, %d コア）の見込み: 約 %.0f 分\n", as.integer(cfg$reps), cores, full_min))
  }
  return(invisible(summary))
}
