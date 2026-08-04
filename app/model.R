# ------------------------------------------------------------------------------
# model.R
#
# Projection model for AGE-related healthcare encounters and expenditures among a
# single annual U.S. birth cohort followed to age 2 years, under alternative
# rotavirus vaccination uptake distributions.
#
# This is a direct re-implementation of the calculations in
#   docs/"RV spreadsheet.xlsx", sheet "Butler et al RV Tables"
# accompanying Butler, Panozzo, Boutzoukas & Brookhart, "Rotavirus Vaccination:
# Impact of New Recommendation."
#
# Structure of the calculation, for each vaccination stratum s, evaluated once
# under the current uptake distribution and once under a scenario distribution
# supplied directly by the reader (typed uptake percentages, not a derived
# shift from a single slider):
#
#   events_s = births * share_s * risk_s
#   cost     = sum_s(hosp_s) * unit_cost_hosp + sum_s(ed_s) * unit_cost_ed
#
# where risk_s is the 2-year cumulative incidence of the outcome from Butler et
# al. (Epidemiology 2021) and unit costs are per-episode costs in 2025 USD, taken
# either from a direct-medical or a societal (direct + indirect) perspective.
# Excess burden and expenditure are the scenario totals minus the baseline
# totals.
#
# The model is deterministic and accounts for direct effects of vaccination only;
# no indirect (herd) protection is assumed, consistent with the published letter.
# ------------------------------------------------------------------------------


# --- Group registry -----------------------------------------------------------
# One row per vaccination stratum. `share`, `risk_h` and `risk_e` are the values
# the app puts in editable cells; the `_lo`/`_hi` columns are the published 95%
# confidence limits, retained for the sensitivity analysis planned as follow-up
# work even though nothing consumes them in this revision.
#
# The two partial-series shares are the person-time split from Butler et al.
# 2021 Table 1, 162196/(162196+323558) = 33.3906% of the 15.3% partially
# vaccinated. Displayed to six decimals: they sum to 15.3 exactly and land
# within $0.43 of the spreadsheet's baseline expenditure.

rv_groups <- function() {
  data.frame(
    id        = c("unvax", "p1", "p2", "full"),
    label     = c("Unvaccinated", "Partial RV5 (1 dose)",
                  "Partial RV5 (2 doses)", "Full series"),
    share     = c(13.9, 5.108756, 10.191244, 70.7),
    risk_h    = c(0.88, 0.80, 0.61, 0.47),
    risk_e    = c(4.36, 4.57, 4.23, 3.15),
    risk_h_lo = c(0.79, 0.62, 0.52, 0.45),
    risk_h_hi = c(0.97, 1.02, 0.71, 0.49),
    risk_e_lo = c(4.17, 4.04, 3.95, 3.09),
    risk_e_hi = c(4.57, 5.16, 4.54, 3.21),
    stringsAsFactors = FALSE
  )
}


# --- Scalar registry ----------------------------------------------------------
# Population and cost assumptions, which remain sliders. `low`/`high` are the
# plausible ranges, retained for the same reason as the group bounds above.

rv_scalars <- function() {
  s <- function(id, label, default, min, max, step, low, high, source, widget) {
    data.frame(id = id, label = label, default = default,
      min = min, max = max, step = step, low = low, high = high,
      source = source, widget = widget, stringsAsFactors = FALSE)
  }

  do.call(rbind, list(
    s("births", "Annual U.S. births",
      3622673, 3000000, 4200000, 1000, 3441539, 3803807,
      "CDC Vital Statistics Rapid Release No. 38 (provisional 2024); range +/-5%",
      "slider"),
    s("c_hosp", "Direct medical cost per hospitalization ($)",
      19251.56, 0, 60000, 10, 14438.67, 24064.45,
      "Karve et al. 2014, CPI-inflated to Jan 2025; range +/-25%",
      "numeric"),
    s("c_ed", "Direct medical cost per ED visit ($)",
      781.83, 0, 4000, 1, 586.37, 977.29,
      "Karve et al. 2014, CPI-inflated to Jan 2025; range +/-25%",
      "numeric"),
    # Spreadsheet "Indirect costs" cell N45 = H45 + P24, i.e. two days of
    # $1,117 weekly earnings taken over a 7-day week, plus $104.64 of median
    # out-of-pocket costs: 1117 / 7 * 2 + 104.64 = 423.782857142857...
    #
    # Rounded here to whole cents, because it is a cost. The spreadsheet never
    # rounded it -- Excel carries the repeating decimal from 1117/7 straight
    # through -- so its dollar cells sit $17 to $420 above this model. Nothing
    # the letter reports moves: both $34.5M and $103.5M are unchanged, as are
    # footnote d's percentages to four decimals. test-model.R pins the gap and
    # proves it is due to this rounding alone.
    s("c_indirect", "Indirect (productivity) cost per episode ($)",
      423.78, 0, 2000, 1, 317.84, 529.73,
      paste("2 days of median weekly earnings (BLS CPS 2023, $1,117/wk) plus",
            "out-of-pocket costs; applied identically to ED and inpatient",
            "episodes; range +/-25%"),
      "numeric")
  ))
}


rv_scalar_defaults <- function() {
  tab <- rv_scalars()
  stats::setNames(as.list(tab$default), tab$id)
}


# --- Risk-difference confidence limits ----------------------------------------
# Butler et al. 2021 Table 1 cell E18 and Table 2 cell E59: the two-year risk
# difference between the full RV5 series and no vaccination, percentage points.
#
#   hospitalization   -0.40 (-0.50, -0.31)
#   ED visit          -1.22 (-1.43, -1.00)
#
# `rv_apply_rd()` sets the full-series risks so that this risk difference takes
# a given value, holding the unvaccinated risks fixed. That is the contrast the
# authors estimated and bootstrapped, and because the scenario moves people
# strictly between these two strata, the projected excess is exactly linear in
# it -- so a bound on the risk difference maps directly onto a bound on the
# excess, with no further assumption.
#
# Note the point estimates disagree with the risk table by 0.01 in each
# direction: differencing the rounded risks gives -0.41 and -1.21, while the
# paper reports -0.40 and -1.22. Both are rounded views of the same unrounded
# quantity. Anchoring on the unvaccinated risk, as here, is the reading that
# matches "set the risk difference to its confidence limit".

rv_rd_bounds <- function() {
  list(
    lower = c(hosp = -0.50, ed = -1.43),   # larger protective effect
    point = c(hosp = -0.40, ed = -1.22),
    upper = c(hosp = -0.31, ed = -1.00)    # smaller protective effect
  )
}


#' Set the full-series risks to a given risk difference vs unvaccinated
#'
#' @param groups Data frame shaped like `rv_groups()`.
#' @param rd     Named numeric with elements `hosp` and `ed`, in percentage
#'               points (negative = protective).
#' @return `groups` with `risk_h` and `risk_e` of the last row replaced.
rv_apply_rd <- function(groups, rd) {
  n <- nrow(groups)
  groups$risk_h[n] <- groups$risk_h[1] + rd[["hosp"]]
  groups$risk_e[n] <- groups$risk_e[1] + rd[["ed"]]
  groups
}


# --- Published scenario columns -----------------------------------------------
# Derived from the current column rather than transcribed, so the two cannot
# drift apart. Matches spreadsheet rows J23-J26, J31-J34 and J41-J44: the shift
# moves percentage points from the full series into unvaccinated, holding both
# partial strata fixed.

rv_scenarios <- function() {
  base <- rv_groups()$share
  mk <- function(pp) {
    v <- base
    v[1] <- v[1] + pp
    v[4] <- v[4] - pp
    v
  }
  list("10%" = mk(10), "20%" = mk(20), "30%" = mk(30))
}


# --- Input coercion -----------------------------------------------------------
# NULL means the input has not initialised yet, so fall back to the default. NA
# means the user cleared the box, which reads as zero: substituting the default
# would fight them mid-typing, and leaving NA propagates into plot limits and
# crashes the render.

rv_num <- function(x, default = 0) {
  if (is.null(x)) return(default)
  if (length(x) != 1 || is.na(x) || !is.finite(x)) return(0)
  as.numeric(x)
}


#' Project AGE burden and cost under two uptake distributions
#'
#' @param groups     Data frame shaped like `rv_groups()`. Only `share`,
#'                   `risk_h`, `risk_e` and `label` are read. Percentages are on
#'                   the 0-100 scale.
#' @param scen_share Numeric vector of scenario shares (0-100), in group order.
#' @param scalars    Named list of scalar parameters (see `rv_scalar_defaults`).
#' @param societal   If TRUE, unit costs include indirect (productivity) costs;
#'                   if FALSE, direct medical costs only.
#' @param cohorts    Number of consecutive annual birth cohorts. Estimates are
#'                   additive across cohorts, so this is a simple multiplier.
#'
#' @return A list with `strata` (per-stratum detail under both distributions),
#'   `baseline`, `scenario` and `excess` summaries.
rv_project <- function(groups, scen_share, scalars, societal = TRUE,
                       cohorts = 1) {

  base_share <- groups$share / 100
  scen_share <- as.numeric(scen_share) / 100
  risk_h <- groups$risk_h / 100
  risk_e <- groups$risk_e / 100

  unit_h <- scalars$c_hosp + if (isTRUE(societal)) scalars$c_indirect else 0
  unit_e <- scalars$c_ed   + if (isTRUE(societal)) scalars$c_indirect else 0

  summarise <- function(sh) {
    hosp <- scalars$births * sh * risk_h * cohorts
    ed   <- scalars$births * sh * risk_e * cohorts
    list(
      shares = sh,
      hosp = hosp, ed = ed,
      hosp_total = sum(hosp), ed_total = sum(ed),
      cost_hosp = sum(hosp) * unit_h,
      cost_ed   = sum(ed) * unit_e,
      cost_total = sum(hosp) * unit_h + sum(ed) * unit_e
    )
  }

  b <- summarise(base_share)
  s <- summarise(scen_share)

  pct <- function(scen, base) if (isTRUE(base > 0)) 100 * (scen - base) / base else NA_real_

  strata <- data.frame(
    stratum = groups$label,
    share_base = 100 * b$shares,
    share_scen = 100 * s$shares,
    hosp_base = b$hosp, hosp_scen = s$hosp,
    ed_base = b$ed, ed_scen = s$ed,
    row.names = NULL, stringsAsFactors = FALSE
  )
  strata$hosp_excess <- strata$hosp_scen - strata$hosp_base
  strata$ed_excess   <- strata$ed_scen - strata$ed_base

  list(
    strata = strata,
    unit_cost_hosp = unit_h,
    unit_cost_ed = unit_e,
    share_sum_base = 100 * sum(base_share),
    share_sum_scen = 100 * sum(scen_share),
    baseline = b,
    scenario = s,
    excess = list(
      hosp = s$hosp_total - b$hosp_total,
      ed   = s$ed_total - b$ed_total,
      cost_hosp = s$cost_hosp - b$cost_hosp,
      cost_ed   = s$cost_ed - b$cost_ed,
      cost_total = s$cost_total - b$cost_total,
      pct_hosp = pct(s$hosp_total, b$hosp_total),
      pct_ed   = pct(s$ed_total, b$ed_total),
      pct_cost = pct(s$cost_total, b$cost_total)
    )
  )
}


# --- Small utilities ----------------------------------------------------------

# Defined locally rather than relying on rlang or R >= 4.4, so the app runs on
# whatever R version the Shinylive runtime provides.
`%||%` <- function(x, y) if (is.null(x)) y else x


# --- Formatting helpers -------------------------------------------------------

fmt_n   <- function(x, digits = 0) formatC(x, format = "f", digits = digits, big.mark = ",")
fmt_usd <- function(x) paste0(ifelse(x < 0, "-$", "$"), fmt_n(abs(x)))

fmt_usd_short <- function(x) {
  s <- ifelse(x < 0, "-", "")
  a <- abs(x)
  ifelse(a >= 1e9, sprintf("%s$%.2fB", s, a / 1e9),
    ifelse(a >= 1e6, sprintf("%s$%.1fM", s, a / 1e6),
      ifelse(a >= 1e3, sprintf("%s$%.0fK", s, a / 1e3), sprintf("%s$%.0f", s, a))))
}
