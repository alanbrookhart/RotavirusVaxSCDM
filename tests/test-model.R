# ------------------------------------------------------------------------------
# tests/test-model.R
#
# Regression checks: the R model must reproduce the values in
# docs/"RV spreadsheet.xlsx" (sheet "Butler et al RV Tables") to within rounding.
#
# Run with:  Rscript tests/test-model.R
# ------------------------------------------------------------------------------

source(file.path("app", "model.R"))

g    <- rv_groups()
sc   <- rv_scalar_defaults()
scen <- rv_scenarios()

check <- function(label, observed, expected, tol) {
  ok <- abs(observed - expected) <= tol
  cat(sprintf("%-52s %16.4f  vs %16.4f  %s\n", label, observed, expected,
    if (ok) "OK" else "FAIL"))
  if (!ok) stop("Mismatch in: ", label, call. = FALSE)
  invisible(TRUE)
}

cat("\nBaseline, published uptake (13.9 / 15.3 / 70.7), societal costs\n")
cat(strrep("-", 100), "\n")

# Scenario column set equal to the current column: no excess, and the baseline
# totals are the spreadsheet's current-uptake figures.
b <- rv_project(g, g$share, sc, societal = TRUE)

check("Hospitalizations (xlsx K19)", b$baseline$hosp_total,  20201.714152, 0.01)
check("ED visits (xlsx K60)",        b$baseline$ed_total,   126708.413902, 0.01)
check("Total expenditures (xlsx W23)", b$baseline$cost_total, 550236945.15, 1)
check("Zero excess when scenario equals current", b$excess$cost_total, 0, 1e-6)

cat("\nPrefill scenario columns match spreadsheet rows J23-J26 / J31-J34 / J41-J44\n")
cat(strrep("-", 100), "\n")

# Guards the prefill constants against drift. Partial strata are held fixed.
prefill <- list(
  "10%" = c(23.9, 5.108756, 10.191244, 60.7),
  "20%" = c(33.9, 5.108756, 10.191244, 50.7),
  "30%" = c(43.9, 5.108756, 10.191244, 40.7)
)
for (s in names(prefill)) {
  for (k in seq_len(4)) {
    check(sprintf("Prefill %s, %s", s, g$label[k]), scen[[s]][k], prefill[[s]][k], 1e-9)
  }
}

cat("\nExcess burden by scenario\n")
cat(strrep("-", 100), "\n")

# Spreadsheet cells: hosp L27/L35/L45, ED L68/L75/L83, cost X24/X25/X26
expected <- list(
  "10%" = c(hosp = 1485.29593,  ed = 4383.43433,  cost = 34508431.45),
  "20%" = c(hosp = 2970.59186,  ed = 8766.86866,  cost = 69016862.91),
  "30%" = c(hosp = 4455.88779,  ed = 13150.30299, cost = 103525294.36)
)

for (s in names(expected)) {
  r <- rv_project(g, scen[[s]], sc, societal = TRUE)
  e <- expected[[s]]
  check(sprintf("Excess hospitalizations, %s", s), r$excess$hosp, e[["hosp"]], 0.01)
  check(sprintf("Excess ED visits, %s", s),        r$excess$ed,   e[["ed"]],   0.01)
  check(sprintf("Excess expenditures, %s", s), r$excess$cost_total, e[["cost"]], 1)
}

cat("\nRelative excess -- Figure 2 footnotes b, c, d (xlsx sheet 'Monica')\n")
cat(strrep("-", 100), "\n")

r10 <- rv_project(g, scen[["10%"]], sc, societal = TRUE)
r30 <- rv_project(g, scen[["30%"]], sc, societal = TRUE)
check("Relative excess hosp., 10% (Monica C9)", r10$excess$pct_hosp,  7.352326, 0.001)
check("Relative excess ED,    10% (Monica B9)", r10$excess$pct_ed,    3.459466, 0.001)
check("Relative excess cost,  10% (Monica D9)", r10$excess$pct_cost,  6.271558, 0.001)
check("Relative excess cost,  30% (Monica D11)", r30$excess$pct_cost, 18.814675, 0.001)

cat("\nCost perspective reconciliation with the published letter\n")
cat(strrep("-", 100), "\n")

# The letter reports $32.0M for a 10% shift and $103.5M for a 30% shift. These
# use different perspectives: $32.0M is direct medical only, $103.5M is societal.
d10 <- rv_project(g, scen[["10%"]], sc, societal = FALSE)$excess$cost_total
d30 <- rv_project(g, scen[["30%"]], sc, societal = FALSE)$excess$cost_total
check("Excess expenditures, 10%, direct only", d10, 32021364, 5000)
cat(sprintf("%-52s %16.4f\n", "Excess expenditures, 30%, direct only", d30))

cat("\nInternal consistency\n")
cat(strrep("-", 100), "\n")

check("Three cohorts = 3 x one cohort",
  rv_project(g, scen[["10%"]], sc, cohorts = 3)$excess$hosp,
  3 * expected[["10%"]][["hosp"]], 0.01)

# A scenario that moves people into partial rather than out of vaccination --
# expressible only now that the scenario column is typed rather than derived.
mixed <- c(18.9, 5.108756, 15.191244, 60.7)
rm_ <- rv_project(g, mixed, sc, societal = TRUE)
stopifnot(rm_$excess$hosp > 0, rm_$excess$hosp < expected[["10%"]][["hosp"]])
cat("Mixed scenario (some to partial) yields excess below the all-to-unvax case: OK\n")

cat("\nBlank-cell handling\n")
cat(strrep("-", 100), "\n")

check("rv_num(NULL, 42) falls back to the default", rv_num(NULL, 42), 42, 1e-9)
check("rv_num(NA, 42) reads as zero",               rv_num(NA_real_, 42), 0, 1e-9)
check("rv_num(NaN, 42) reads as zero",              rv_num(NaN, 42), 0, 1e-9)
check("rv_num(7, 42) passes the value through",     rv_num(7, 42), 7, 1e-9)

# An empty cell must not error: shares of zero are a valid, if degenerate, input.
gz <- g; gz$share <- c(0, 0, 0, 0)
z <- rv_project(gz, gz$share, sc, societal = TRUE)
stopifnot(z$baseline$hosp_total == 0, is.na(z$excess$pct_hosp))
cat("All-zero shares produce zero totals and NA percentages without error: OK\n")

cat("\nAll checks passed.\n\n")
