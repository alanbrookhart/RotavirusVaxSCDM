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

# These are the MODEL's own figures, not the spreadsheet's. Three deliberate
# departures move the baseline; none can touch the excess: the three cost inputs are whole
# dollars where the spreadsheet carries Karve's cents and an unrounded 1117/7
# intermediate, and the one-dose weight is the person-time ratio to one decimal.
# The weight moves the counts as well as the cost -- by 0.10 of a hospitalization
# and 0.18 of an ED visit, or 0.0005%.
#
# The reproduction proof lives in the "Spreadsheet equivalence" block below,
# which restores every rounded input and recovers all six cells exactly. If that
# block passes and these fail, a default moved; if both fail, the model diverged.
check("Hospitalizations, model default", b$baseline$hosp_total,  20206.907727, 0.001)
check("ED visits, model default",        b$baseline$ed_total,   126846.083759, 0.001)
check("Total expenditures, model default", b$baseline$cost_total, 550567493.44, 0.01)
check("Shares sum to 100%", sum(g$share), 100, 1e-9)
check("Zero excess when scenario equals current", b$excess$cost_total, 0, 1e-6)

cat("\nPrefill scenario columns match spreadsheet rows J23-J26 / J31-J34 / J41-J44\n")
cat(strrep("-", 100), "\n")

# Guards the prefill constants against drift. The partially vaccinated stratum
# is held fixed.
prefill <- list(
  "10%" = c(23.9, 15.4, 60.7),
  "20%" = c(33.9, 15.4, 50.7),
  "30%" = c(43.9, 15.4, 40.7)
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
  "10%" = c(hosp = 1485.29593,  ed = 4383.43433,  cost = 34511104.52),
  "20%" = c(hosp = 2970.59186,  ed = 8766.86866,  cost = 69022209.04),
  "30%" = c(hosp = 4455.88779,  ed = 13150.30299, cost = 103533313.56)
)

for (s in names(expected)) {
  r <- rv_project(g, scen[[s]], sc, societal = TRUE)
  e <- expected[[s]]
  check(sprintf("Excess hospitalizations, %s", s), r$excess$hosp, e[["hosp"]], 0.01)
  check(sprintf("Excess ED visits, %s", s),        r$excess$ed,   e[["ed"]],   0.01)
  check(sprintf("Excess expenditures, %s", s), r$excess$cost_total, e[["cost"]], 0.01)
}

cat("\nSpreadsheet equivalence: rounding is the ONLY difference\n")
cat(strrep("-", 100), "\n")

# Undo BOTH deliberate roundings -- the whole-dollar costs and the two-decimal
# partially vaccinated risks -- and the model must reproduce all six spreadsheet
# cells. It does so exactly, which is the proof that those roundings are the only
# thing separating this model from the source.
sc_x <- sc
sc_x$c_hosp     <- 19251.56
sc_x$c_ed       <- 781.83
sc_x$c_indirect <- 1117 / 7 * 2 + 104.64
# The partially vaccinated risks the letter reports (0.67, 4.34) are the
# share-weighted average of Butler's one- and two-dose levels, rounded to two
# decimals. Restore the unrounded average to undo that rounding too.
w_pt <- 162196 / (162196 + 323558)
g_x  <- g
g_x$risk_h[2] <- w_pt * 0.80 + (1 - w_pt) * 0.61
g_x$risk_e[2] <- w_pt * 4.57 + (1 - w_pt) * 4.23
# And restore Sederdahl's rounded 15.3, which the app carries as 15.4 so the
# distribution totals 100%. The spreadsheet uses 15.3 and therefore sums to 99.9.
g_x$share[2] <- 15.3
# Scenario columns must be built from g_x too. If the baseline carried 15.3 and
# the scenario 15.4 the partially vaccinated stratum would stop cancelling and
# would leak into the excess.
scen_x <- lapply(c("10%" = 10, "20%" = 20, "30%" = 30), function(sh) {
  v <- g_x$share; v[1] <- v[1] + sh; v[3] <- v[3] - sh; v
})
b_x  <- rv_project(g_x, g_x$share, sc_x)

check("Hospitalizations (xlsx K19)",   b_x$baseline$hosp_total,  20201.714152, 0.001)
check("ED visits (xlsx K60)",          b_x$baseline$ed_total,   126708.413902, 0.001)
check("Baseline expenditures (xlsx W23)", b_x$baseline$cost_total, 550236945.15, 1)
xls <- c("10%" = 34508431.45, "20%" = 69016862.91, "30%" = 103525294.36)
for (s in names(xls)) {
  check(sprintf("Excess expenditures, %s (xlsx X2%s)", s, substr(s, 1, 1)),
    rv_project(g_x, scen_x[[s]], sc_x)$excess$cost_total, xls[[s]], 1)
}

# The rounding must stay below reporting precision. Asserted on what the letter
# actually prints, not on an absolute dollar bound -- a bound would have to be
# re-tuned every time a cost default moved, and would not say anything about
# whether the published figures still hold.
for (s in c("10%", "30%")) {
  rounded <- fmt_usd_short(rv_project(g, scen[[s]], sc)$excess$cost_total)
  exact   <- fmt_usd_short(rv_project(g_x, scen_x[[s]], sc_x)$excess$cost_total)
  if (!identical(rounded, exact)) {
    stop(sprintf("Rounding changed the reported %s figure: %s vs %s", s, rounded, exact))
  }
  cat(sprintf("Reported %s figure unchanged by rounding: %s\n", s, rounded))
}

# Footnote d's percentages must still round to the published 6.3% and 18.8%.
for (s in c("10%", "30%")) {
  pr <- rv_project(g, scen[[s]], sc)$excess$pct_cost
  px <- rv_project(g_x, scen_x[[s]], sc_x)$excess$pct_cost
  check(sprintf("Footnote d %s, whole-dollar vs exact costs", s), round(pr, 1), round(px, 1), 1e-9)
}

# Relative size of the rounding, so a future change that inflates it is visible
# in the output rather than silently absorbed.
dev <- abs(rv_project(g, scen[["30%"]], sc)$excess$cost_total /
           rv_project(g_x, scen_x[["30%"]], sc_x)$excess$cost_total - 1)
check("Rounding shifts the 30% excess by under 0.05%", dev < 5e-4, TRUE, 0)
cat(sprintf("  (actual relative shift: %.5f%%)\n", 100 * dev))

cat("\nCombined partially vaccinated stratum\n")
cat(strrep("-", 100), "\n")

# The letter reports ONE partially vaccinated stratum. Its risks are the
# share-weighted average of Butler's one- and two-dose RV5 levels at the
# person-time split, rounded to two decimals -- check that provenance holds, so
# a future edit to either level or to the weight shows up here.
w_pt <- 162196 / (162196 + 323558)
check("Partial hosp risk is the rounded weighted average",
  g$risk_h[2], round(w_pt * 0.80 + (1 - w_pt) * 0.61, 2), 1e-12)
check("Partial ED risk is the rounded weighted average",
  g$risk_e[2], round(w_pt * 4.57 + (1 - w_pt) * 4.23, 2), 1e-12)
check("Partial hosp risk matches the letter (67 per 10,000)", g$risk_h[2], 0.67, 1e-12)
check("Partial ED risk matches the letter (434 per 10,000)", g$risk_e[2], 4.34, 1e-12)

# Collapsing the two levels is an identity, not an approximation: the model is
# linear in the shares, so a single stratum at the weighted average reproduces an
# explicit two-stratum build exactly. Shown here at the person-time split, with
# the unrounded average so the comparison isolates the collapse itself.
ps <- g$share[2]   # partially vaccinated share, read from the registry
two_stratum <- function(w) data.frame(
  id     = c("unvax", "p1", "p2", "full"),
  label  = c("Unvaccinated", "Partial 1 dose", "Partial 2 doses", "Fully vaccinated"),
  share  = c(g$share[1], ps * w, ps * (1 - w), g$share[3]),
  risk_h = c(0.88, 0.80, 0.61, 0.47),
  risk_e = c(4.36, 4.57, 4.23, 3.15),
  stringsAsFactors = FALSE)

for (w in c(0, 0.2, w_pt, 0.5, 1)) {
  g1 <- g
  g1$risk_h[2] <- w * 0.80 + (1 - w) * 0.61
  g1$risk_e[2] <- w * 4.57 + (1 - w) * 4.23
  g2 <- two_stratum(w)
  s1 <- g1$share; s1[1] <- s1[1] + 30; s1[3] <- s1[3] - 30
  s2 <- g2$share; s2[1] <- s2[1] + 30; s2[4] <- s2[4] - 30
  r1 <- rv_project(g1, s1, sc); r2 <- rv_project(g2, s2, sc)
  # One cent, not machine epsilon: the two builds sum the same terms in a
  # different order, and 1 ulp on ~$5.5e8 is already 1.2e-7.
  check(sprintf("Combined == two strata at w=%.4f (baseline)", w),
    r1$baseline$cost_total, r2$baseline$cost_total, 0.01)
  check(sprintf("Combined == two strata at w=%.4f (excess)", w),
    r1$excess$cost_total, r2$excess$cost_total, 0.01)
}

# And the split cannot move the excess at all, which is why the app no longer
# exposes it as a control.
exc <- vapply(c(0, 0.2, 0.5, 1), function(w) {
  gg <- g
  gg$risk_h[2] <- w * 0.80 + (1 - w) * 0.61
  gg$risk_e[2] <- w * 4.57 + (1 - w) * 4.23
  v <- gg$share; v[1] <- v[1] + 30; v[3] <- v[3] - 30
  rv_project(gg, v, sc)$excess$cost_total
}, numeric(1))
check("The partial split has no effect on the excess", diff(range(exc)), 0, 0.01)

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

# The partially vaccinated ED risk sits only 0.02 below the unvaccinated
# reference -- 4.34 against 4.36. That margin is worth pinning: Butler's one-dose
# level (4.57) is ABOVE the unvaccinated risk, so a partially vaccinated group
# weighted more heavily towards one dose would cross the constraint. Asserted so
# that any future edit to those risks makes the proximity visible.
check("Partial ED risk sits below the unvaccinated reference",
  g$risk_e[1] - g$risk_e[2], 0.02, 1e-12)
check("Butler's one-dose ED level is itself above unvaccinated",
  4.57 > g$risk_e[1], TRUE, 0)

gp <- g; gp$risk_e[2] <- 4.57   # partially vaccinated weighted wholly to one dose
check("A one-dose-only partial group would be capped",
  length(rv_clamp_harm(gp)$capped), 1, 0)

# Capping never raises a risk, and never touches the unvaccinated row.
for (bump in list(c(0, 0), c(1, 0), c(0, 1), c(2, 2))) {
  gg <- g
  gg$risk_h[2:3] <- gg$risk_h[2:3] + bump[1]
  gg$risk_e[2:3] <- gg$risk_e[2:3] + bump[2]
  cc <- rv_clamp_harm(gg)
  stopifnot(all(cc$groups$risk_h <= gg$risk_h + 1e-12),
            all(cc$groups$risk_e <= gg$risk_e + 1e-12),
            identical(cc$groups$risk_h[1], gg$risk_h[1]),
            identical(cc$groups$risk_e[1], gg$risk_e[1]))
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

# Asserted against the spreadsheet with every rounding undone, so these remain a
# genuine check on the Monica sheet rather than on this model's roundings.
x10 <- rv_project(g_x, scen_x[["10%"]], sc_x)$excess
x30 <- rv_project(g_x, scen_x[["30%"]], sc_x)$excess
check("Relative excess hosp., 10% (Monica C9)", x10$pct_hosp,  7.352326, 0.001)
check("Relative excess ED,    10% (Monica B9)", x10$pct_ed,    3.459466, 0.001)
check("Relative excess cost,  10% (Monica D9)", x10$pct_cost,  6.271558, 0.001)
check("Relative excess cost,  30% (Monica D11)", x30$pct_cost, 18.814675, 0.001)

# The model's own figures, which the rounding shifts by under 0.03 percentage
# points -- still 7.4 / 3.5 / 6.3 and 18.8 as the letter reports them.
r10 <- rv_project(g, scen[["10%"]], sc)$excess
r30 <- rv_project(g, scen[["30%"]], sc)$excess
check("Model relative excess hosp., 10%", r10$pct_hosp, 7.350437, 0.001)
check("Model relative excess ED,   10%", r10$pct_ed,   3.455711, 0.001)
check("Model relative excess cost, 10%", r10$pct_cost, 6.268279, 0.001)
check("Model relative excess cost, 30%", r30$pct_cost, 18.804836, 0.001)
for (nm in c("hosp10", "ed10", "cost10", "cost30")) {
  pair <- switch(nm,
    hosp10 = c(r10$pct_hosp, x10$pct_hosp), ed10 = c(r10$pct_ed, x10$pct_ed),
    cost10 = c(r10$pct_cost, x10$pct_cost), cost30 = c(r30$pct_cost, x30$pct_cost))
  check(sprintf("%s rounds the same either way", nm),
    round(pair[1], 1), round(pair[2], 1), 1e-9)
}

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
