# simkit.R のテスト: 条件表の順序、乱数の再現性、途中保存、MCSE の式。
source("../simkit.R")

test_that("条件表は最初の変数が最も速く変わる", {
  d <- make_design(list(n = c(10, 20), dist = c("a", "b")))
  expect_equal(d$cond_id, 1:4)
  expect_equal(d$n, c(10, 20, 10, 20))
  expect_equal(d$dist, c("a", "a", "b", "b"))
})

test_that("同じ seed なら同じ乱数列、条件・反復が違えば別の乱数列", {
  a <- rep_seeds(123, 2, 3)
  b <- rep_seeds(123, 2, 3)
  expect_identical(a, b)
  expect_false(identical(a[[1]], a[[2]]))
  expect_false(identical(rep_seeds(123, 1, 1)[[1]], rep_seeds(123, 2, 1)[[1]]))
})

test_that("config.yaml の n や yes は真偽値にならない", {
  dir <- tempfile()
  dir.create(dir)
  writeLines(c("slug: x", "seed: 1", "reps: 2", "pilot_reps: 1",
               "design:", "  n: [10, 20]", "  pretest: [yes, no]", "  flag: [true, false]"),
             file.path(dir, "config.yaml"))
  cfg <- read_config(dir)
  expect_equal(names(cfg$design), c("n", "pretest", "flag"))
  expect_equal(cfg$design$pretest, c("yes", "no"))
  expect_equal(cfg$design$flag, c(TRUE, FALSE))
})

model <- list(
  generate = function(cond) rnorm(cond$n),
  analyse = function(dat, cond) c(m = mean(dat))
)

test_that("並列数を変えても結果は同じ", {
  skip_on_os("windows")
  one <- run_condition(list(n = 5), 1, 99, 1:20, model, cores = 1)
  two <- run_condition(list(n = 5), 1, 99, 1:20, model, cores = 2)
  heavy <- run_condition(list(n = 5), 1, 99, 1:20, model, cores = 2, heavy = TRUE)
  expect_identical(one$results, two$results)
  expect_identical(one$results, heavy$results)
})

test_that("途中保存のブロックに分けて回しても結果は同じ", {
  whole <- run_condition(list(n = 5), 3, 99, 1:20, model, cores = 1)
  parts <- combine_blocks(list(
    run_condition(list(n = 5), 3, 99, 1:7, model, cores = 1),
    run_condition(list(n = 5), 3, 99, 8:20, model, cores = 1)
  ))
  expect_identical(whole$results, parts$results)
})

test_that("analyse() のエラーは記録され、他の反復は続く", {
  bad <- list(
    generate = function(cond) rnorm(1),
    analyse = function(dat, cond) if (dat > 0) stop("正の値") else c(m = dat)
  )
  out <- run_condition(list(n = 1), 1, 7, 1:30, bad, cores = 1)
  expect_equal(nrow(out$results) + nrow(out$errors), 30)
  expect_true(all(out$errors$error == "正の値"))
})

test_that("MCSE は Morris et al. (2019) の式どおり", {
  x <- c(1, 2, 3, 4)
  b <- perf_bias(x, 2)
  expect_equal(b[["estimate"]], 0.5)
  expect_equal(b[["mcse"]], sd(x) / 2)
  e <- perf_empse(x)
  expect_equal(e[["mcse"]], sd(x) / sqrt(6))
  r <- perf_rate(c(TRUE, FALSE, TRUE, TRUE))
  expect_equal(r[["estimate"]], 0.75)
  expect_equal(r[["mcse"]], sqrt(0.75 * 0.25 / 4))
  m <- perf_mse(x, 2)
  e2 <- (x - 2)^2
  expect_equal(m[["estimate"]], mean(e2))
  expect_equal(m[["mcse"]], sqrt(sum((e2 - mean(e2))^2) / (4 * 3)))
  expect_equal(perf_coverage(c(0, 0, 3), c(1, 3, 4), 2)[["estimate"]], 1 / 3)
})
