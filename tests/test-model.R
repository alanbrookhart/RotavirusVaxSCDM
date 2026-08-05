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
check("Zero excess when scenario equals current", b$excess$cost_total, 0, 1e-6)

# Dollar figures are asserted against this model's own arithmetic to the cent,
# NOT against the spreadsheet, because `c_indirect` is deliberately rounded to
# whole cents while the spreadsheet carries the repeating decimal from 1117/7.
# The reproduction proof lives in the "Spreadsheet equivalence" block below: it
# shows that restoring the unrounded intermediate recovers W23 and X24-X26
# exactly, so this rounding is the only difference between the two.
check("Total expenditures, rounded cost", b$baseline$cost_total, 550236525.40, 0.01)

cat("\nPrefill scenario columns match spreadsheet rows J23-J26 / J31-J34 / J41-J44\n")
cat(strrep("-", 100), "\n")

# Guards the prefill constants against drift. The partially vaccinated stratum
# is held fixed.
prefill <- list(
  "10%" = c(23.9, 15.3, 60.7),
  "20%" = c(33.9, 15.3, 50.7),
  "30%" = c(43.9, 15.3, 40.7)
)
for (s in names(prefill)) {
  for (k in seq_len(3)) {
    check(sprintf("Prefill %s, %s", s, g$label[k]), scen[[s]][k], prefill[[s]][k], 1e-9)
  }
}

cat("\nExcess burden by scenario\n")
cat(strrep("-", 100), "\n")

# Encounter counts are spreadsheet cells (hosp L27/L35/L45, ED L68/L75/L83) and
# do not involve cost, so they are asserted against the spreadsheet directly.
# Costs are this model's own values -- see the note above.
expected <- list(
  "10%" = c(hosp = 1485.29593,  ed = 4383.43433,  cost = 34508414.69),
  "20%" = c(hosp = 2970.59186,  ed = 8766.86866,  cost = 69016829.37),
  "30%" = c(hosp = 4455.88779,  ed = 13150.30299, cost = 103525244.06)
)

for (s in names(expected)) {
  r <- rv_project(g, scen[[s]], sc, societal = TRUE)
  e <- expected[[s]]
  check(sprintf("Excess hospitalizations, %s", s), r$excess$hosp, e[["hosp"]], 0.01)
  check(sprintf("Excess ED visits, %s", s),        r$excess$ed,   e[["ed"]],   0.01)
  check(sprintf("Excess expenditures, %s", s), r$excess$cost_total, e[["cost"]], 0.01)
}

cat("\nSpreadsheet equivalence: the rounded cent is the ONLY difference\n")
cat(strrep("-", 100), "\n")

# Restore the spreadsheet's unrounded intermediate (Indirect costs!N45) and the
# model must reproduce W23 and X24-X26 to within $1, as it did before the
# rounding. If this block fails, the model and the spreadsheet have genuinely
# diverged; if only the block above fails, a cost input moved.
sc_x <- sc; sc_x$c_indirect <- 1117 / 7 * 2 + 104.64
check("Baseline expenditures (xlsx W23)",
  rv_project(g, g$share, sc_x)$baseline$cost_total, 550236945.15, 1)
xls <- c("10%" = 34508431.45, "20%" = 69016862.91, "30%" = 103525294.36)
for (s in names(xls)) {
  check(sprintf("Excess expenditures, %s (xlsx X2%s)", s, substr(s, 1, 1)),
    rv_project(g, scen[[s]], sc_x)$excess$cost_total, xls[[s]], 1)
}

# And the rounding costs less than reporting precision: both figures the letter
# prints are unchanged, as are footnote d's percentages to four decimals.
check("Rounding shifts the 30% excess by under $100",
  abs(rv_project(g, scen[["30%"]], sc)$excess$cost_total -
      rv_project(g, scen[["30%"]], sc_x)$excess$cost_total) < 100, TRUE, 0)

cat("\nCombined partially vaccinated stratum\n")
cat(strrep("-", 100), "\n")

# The single blended stratum must reproduce the two-stratum model exactly, for
# ANY weight -- the model is linear in the shares, so this is an identity, not
# an approximation. Compare against an explicit four-row build.
pc <- rv_partial_components()
two_stratum <- function(w_pct, partial_share = 15.3) {
  w <- w_pct / 100
  data.frame(
    id     = c("unvax", "p1", "p2", "full"),
    label  = c("Unvaccinated", "Partial 1 dose", "Partial 2 doses", "Full series"),
    share  = c(13.9, partial_share * w, partial_share * (1 - w), 70.7),
    risk_h = c(0.88, pc$one_dose[["hosp"]], pc$two_doses[["hosp"]], 0.47),
    risk_e = c(4.36, pc$one_dose[["ed"]],   pc$two_doses[["ed"]],   3.15),
    stringsAsFactors = FALSE
  )
}
for (w in c(0, 20, pc$w_default, 50, 100)) {
  g1 <- rv_groups(w); g2 <- two_stratum(w)
  s1 <- g1$share; s1[1] <- s1[1] + 30; s1[3] <- s1[3] - 30
  s2 <- g2$share; s2[1] <- s2[1] + 30; s2[4] <- s2[4] - 30
  r1 <- rv_project(g1, s1, sc); r2 <- rv_project(g2, s2, sc)
  # Tolerance is one cent, not machine epsilon. These are ~$5.5e8 quantities
  # summed in a different order by the two builds, so an exactly-equal result is
  # not something floating point guarantees across R builds: 1 ulp here is
  # already 1.2e-7. Agreement to the cent is the meaningful claim and is
  # portable; a tighter bound tests the compiler, not the model.
  check(sprintf("Blend == two strata at w=%.4f%% (baseline cost)", w),
    r1$baseline$cost_total, r2$baseline$cost_total, 0.01)
  check(sprintf("Blend == two strata at w=%.4f%% (excess cost)", w),
    r1$excess$cost_total, r2$excess$cost_total, 0.01)
}

# The weight moves the baseline but cannot move the excess, because the
# partially vaccinated are held fixed between the two columns.
exc <- vapply(c(0, 20, 50, 100), function(w) {
  gg <- rv_groups(w); s <- gg$share; s[1] <- s[1] + 30; s[3] <- s[3] - 30
  rv_project(gg, s, sc)$excess$cost_total
}, numeric(1))
# One cent again. The partial stratum's contribution appears in both the
# baseline and the scenario sum and cancels in the subtraction, but it cancels
# arithmetically rather than symbolically -- changing the weight changes the
# rounding of an intermediate. On ~$1e8 a single ulp is 2.3e-8, so a 1e-9 bound
# would be asserting something below the resolution of a double.
check("Weight has no effect on the excess", diff(range(exc)), 0, 0.01)
base <- vapply(c(0, 100), function(w) rv_project(rv_groups(w), rv_groups(w)$share, sc)$baseline$cost_total, numeric(1))
stopifnot(diff(base) != 0)
cat(sprintf("Weight does move the baseline (w=0 vs w=100: %s vs %s): OK\n",
  fmt_usd(base[1]), fmt_usd(base[2])))

check("Default weight is the Butler Table 1 person-time ratio",
  pc$w_default, 100 * 162196 / (162196 + 323558), 1e-12)

cat("\nNo-harm constraint\n")
cat(strrep("-", 100), "\n")

# Inactive at the published values: every vaccinated risk is already below the
# unvaccinated reference.
cl <- rv_clamp_harm(g)
check("Published values need no capping", length(cl$capped), 0, 0)
stopifnot(identical(cl$groups$risk_h, g$risk_h), identical(cl$groups$risk_e, g$risk_e))
cat("Published values pass through unchanged: OK\n")

# A full-series risk above unvaccinated is capped, and the excess it would have
# produced -- negative, i.e. withdrawing vaccination prevents encounters -- is
# eliminated.
g_bad <- g; g_bad$risk_h[nrow(g)] <- 1.50; g_bad$risk_e[nrow(g)] <- 5.00
raw <- rv_project(g_bad, scen[["30%"]], sc)
stopifnot(raw$excess$hosp < 0, raw$excess$cost_total < 0)
cat(sprintf("Unconstrained harmful input gives a NEGATIVE excess (%.0f hosp, %s): as expected\n",
  raw$excess$hosp, fmt_usd(raw$excess$cost_total)))

cl_bad <- rv_clamp_harm(g_bad)
check("Both harmful cells are reported", length(cl_bad$capped), 2, 0)
check("Capped hosp risk equals unvaccinated", cl_bad$groups$risk_h[nrow(g)], g$risk_h[1], 1e-12)
check("Capped ED risk equals unvaccinated",   cl_bad$groups$risk_e[nrow(g)], g$risk_e[1], 1e-12)
fixed <- rv_project(cl_bad$groups, scen[["30%"]], sc)
check("Capped input yields exactly zero excess", fixed$excess$cost_total, 0, 1e-6)

# The constraint binds on a published estimate once the one-dose weight rises:
# the blended ED risk crosses 4.36 at w = (4.36 - 4.23)/0.34 = 38.235%.
thresh <- (4.36 - 4.23) / 0.34 * 100
check("Blend crosses the unvaccinated ED risk at w=38.24%",
  rv_blend_partial(thresh)[["ed"]], 4.36, 1e-9)
check("Just below the threshold, nothing is capped",
  length(rv_clamp_harm(rv_groups(thresh - 0.5))$capped), 0, 0)
check("Just above it, the partial ED risk is capped",
  length(rv_clamp_harm(rv_groups(thresh + 0.5))$capped), 1, 0)
check("Default weight sits below the threshold",
  rv_partial_components()$w_default < thresh, TRUE, 0)

# Capping never raises a risk, and never touches the unvaccinated row.
for (w in c(0, 50, 100)) {
  cc <- rv_clamp_harm(rv_groups(w))
  stopifnot(all(cc$groups$risk_h <= rv_groups(w)$risk_h + 1e-12),
            all(cc$groups$risk_e <= rv_groups(w)$risk_e + 1e-12),
            identical(cc$groups$risk_h[1], rv_groups(w)$risk_h[1]),
            identical(cc$groups$risk_e[1], rv_groups(w)$risk_e[1]))
}
cat("Capping is monotone and leaves the unvaccinated reference alone: OK\n")

cat("\nRisk-difference sensitivity (Butler Table 1 E18, Table 2 E59)\n")
cat(strrep("-", 100), "\n")

rdb <- rv_rd_bounds()
check("RD lower limit, hospitalization", rdb$lower[["hosp"]], -0.50, 1e-12)
check("RD lower limit, ED visit",        rdb$lower[["ed"]],   -1.43, 1e-12)
check("RD upper limit, hospitalization", rdb$upper[["hosp"]], -0.31, 1e-12)
check("RD upper limit, ED visit",        rdb$upper[["ed"]],   -1.00, 1e-12)

# The point bound is derived from the published risks, so applying it must be a
# no-op -- that is what makes the "Best Estimate" button restore the default
# rather than shifting the full-series risk to 0.48 as the paper's rounded
# -0.40 would.
check("RD point, hospitalization", rdb$point[["hosp"]], 0.47 - 0.88, 1e-12)
check("RD point, ED visit",        rdb$point[["ed"]],   3.15 - 4.36, 1e-12)
g_pt <- rv_apply_rd(g, rdb$point)
check("Point bound restores the published hosp risk", g_pt$risk_h[nrow(g)], 0.47, 1e-9)
check("Point bound restores the published ED risk",   g_pt$risk_e[nrow(g)], 3.15, 1e-9)
check("Point bound reproduces the published excess",
  rv_project(g_pt, scen[["30%"]], sc)$excess$cost_total,
  rv_project(g,    scen[["30%"]], sc)$excess$cost_total, 0.01)

# Applying a bound must set the full-series risk to unvaccinated + RD, leave the
# unvaccinated and both partial rows untouched, and reproduce the RD exactly.
g_lo <- rv_apply_rd(g, rdb$lower)
g_hi <- rv_apply_rd(g, rdb$upper)
nf <- nrow(g)   # full series is the last row
check("Lower bound sets hosp risk", g_lo$risk_h[nf], 0.38, 1e-9)
check("Lower bound sets ED risk",   g_lo$risk_e[nf], 2.93, 1e-9)
check("Upper bound sets hosp risk", g_hi$risk_h[nf], 0.57, 1e-9)
check("Upper bound sets ED risk",   g_hi$risk_e[nf], 3.36, 1e-9)
check("Realised RD equals the limit", g_lo$risk_h[nf] - g_lo$risk_h[1], -0.50, 1e-9)
stopifnot(identical(g_lo$risk_h[-nf], g$risk_h[-nf]),
          identical(g_lo$risk_e[-nf], g$risk_e[-nf]))
cat("Unvaccinated and partial rows left untouched: OK\n")

# The excess is linear in the risk difference, so the bounds bracket the point
# estimate and the ratio of excesses equals the ratio of risk differences.
e_lo <- rv_project(g_lo, scen[["30%"]], sc)$excess
e_hi <- rv_project(g_hi, scen[["30%"]], sc)$excess
e_pt <- rv_project(g,    scen[["30%"]], sc)$excess
stopifnot(e_hi$hosp < e_pt$hosp, e_pt$hosp < e_lo$hosp)
cat(sprintf("30%% shift, excess hosp: most conservative %.0f < best estimate %.0f < least conservative %.0f: OK\n",
  e_hi$hosp, e_pt$hosp, e_lo$hosp))
check("Excess scales linearly with the RD", e_lo$hosp / e_hi$hosp, 0.50 / 0.31, 1e-9)

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
mixed <- c(18.9, 20.3, 60.7)
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
gz <- g; gz$share <- rep(0, nrow(g))
z <- rv_project(gz, gz$share, sc, societal = TRUE)
stopifnot(z$baseline$hosp_total == 0, is.na(z$excess$pct_hosp))
cat("All-zero shares produce zero totals and NA percentages without error: OK\n")

cat("\nAll checks passed.\n\n")
