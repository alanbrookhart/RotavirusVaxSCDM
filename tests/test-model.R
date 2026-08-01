# ------------------------------------------------------------------------------
# tests/test-model.R
#
# Regression checks: the R model must reproduce the values in
# docs/"RV spreadsheet.xlsx" (sheet "Butler et al RV Tables") to within rounding.
#
# Run with:  Rscript tests/test-model.R
# ------------------------------------------------------------------------------

source(file.path("app", "model.R"))

p <- rv_defaults()

check <- function(label, observed, expected, tol) {
  ok <- abs(observed - expected) <= tol
  cat(sprintf("%-52s %16.2f  vs %16.2f  %s\n", label, observed, expected,
    if (ok) "OK" else "FAIL"))
  if (!ok) stop("Mismatch in: ", label, call. = FALSE)
  invisible(TRUE)
}

cat("\nBaseline, published uptake (13.9 / 15.3 / 70.7), societal costs\n")
cat(strrep("-", 100), "\n")
b <- rv_project(p, shift = 0, societal = TRUE)

# Spreadsheet cells K19, K60, W23
check("Hospitalizations (xlsx K19)", b$baseline$hosp_total,  20201.714152, 0.01)
check("ED visits (xlsx K60)",        b$baseline$ed_total,   126708.413902, 0.01)
check("Total expenditures (xlsx W23)", b$baseline$cost_total, 550236945.15, 1)

cat("\nExcess burden by shift from fully vaccinated to unvaccinated\n")
cat(strrep("-", 100), "\n")

# Spreadsheet cells: hosp L27/L35/L45, ED L68/L75/L83, cost X24/X25/X26
expected <- list(
  "10" = c(hosp = 1485.29593,  ed = 4383.43433,  cost = 34508431.45),
  "20" = c(hosp = 2970.59186,  ed = 8766.86866,  cost = 69016862.91),
  "30" = c(hosp = 4455.88779,  ed = 13150.30299, cost = 103525294.36)
)

for (s in names(expected)) {
  r <- rv_project(p, shift = as.numeric(s), societal = TRUE)
  e <- expected[[s]]
  check(sprintf("Excess hospitalizations, %s%% shift", s), r$excess$hosp, e[["hosp"]], 0.01)
  check(sprintf("Excess ED visits, %s%% shift", s),        r$excess$ed,   e[["ed"]],   0.01)
  check(sprintf("Excess expenditures, %s%% shift", s), r$excess$cost_total, e[["cost"]], 100)
}

cat("\nCost perspective reconciliation with the published letter\n")
cat(strrep("-", 100), "\n")

# The letter reports $32.0M for a 10% shift and $103.5M for a 30% shift. These
# use different perspectives: $32.0M is direct medical only, $103.5M is societal.
d10 <- rv_project(p, shift = 10, societal = FALSE)$excess$cost_total
d30 <- rv_project(p, shift = 30, societal = FALSE)$excess$cost_total
check("Excess expenditures, 10% shift, direct only", d10, 32021364, 5000)
cat(sprintf("%-52s %16.2f\n", "Excess expenditures, 30% shift, direct only", d30))

cat("\nInternal consistency\n")
cat(strrep("-", 100), "\n")

# Excess is linear in the shift because only two strata move and risks are fixed.
lin <- rv_project(p, shift = 15, societal = TRUE)$excess$hosp
check("Linearity: 15% shift = 1.5 x 10% shift", lin,
  1.5 * expected[["10"]][["hosp"]], 0.01)

# A zero shift must produce no excess.
check("Zero shift yields zero excess cost",
  rv_project(p, shift = 0, societal = TRUE)$excess$cost_total, 0, 1e-6)

# Shifts beyond the fully vaccinated share are clamped.
r <- rv_project(p, shift = 99, societal = TRUE)
check("Shift clamped at fully vaccinated share", r$shift_applied, p$p_full, 1e-9)

# Normalizing shares should raise baseline counts by about 1/0.999.
n <- rv_project(p, shift = 0, societal = TRUE, normalize = TRUE)
check("Normalized baseline hospitalizations", n$baseline$hosp_total,
  b$baseline$hosp_total / 0.999, 0.01)

# Multiple cohorts are additive.
check("Three cohorts = 3 x one cohort",
  rv_project(p, shift = 10, cohorts = 3)$excess$hosp,
  3 * expected[["10"]][["hosp"]], 0.01)

cat("\nTornado sanity\n")
cat(strrep("-", 100), "\n")
tor <- rv_tornado(p, outcome = "excess_cost", shift = 10)
stopifnot(nrow(tor) == nrow(rv_param_table()))
stopifnot(all(tor$swing >= -1e-9))
stopifnot(!is.unsorted(tor$swing))
cat("Most influential parameter: ", tor$label[nrow(tor)],
  sprintf(" (swing %s)\n", fmt_usd(tor$swing[nrow(tor)])), sep = "")
cat("Least influential parameter: ", tor$label[1],
  sprintf(" (swing %s)\n", fmt_usd(tor$swing[1])), sep = "")

cat("\nAll checks passed.\n\n")
