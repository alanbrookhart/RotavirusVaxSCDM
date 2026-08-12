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
# One row per vaccination stratum. `share` and the risks are what the app puts
# in the grid; the `_lo`/`_hi` columns are the published 95% confidence limits.
#
# Risks are the letter's own figures, per 10,000 converted to percent:
# AGE-related hospitalization 88 / 67 / 47 and AGE-related ED visit 436 / 434 /
# 315, for unvaccinated, partially vaccinated and fully vaccinated.
#
# On the partially vaccinated row: Butler et al. estimate that group as TWO
# strata, one dose (0.80% hospitalization, 4.57% ED) and two doses (0.61%,
# 4.23%), while the uptake source (Sederdahl et al. 2019) reports only a single
# lumped 15.3%. The letter's 0.67% and 4.34% are the share-weighted average of
# the two levels, taking 33.4% of the partially vaccinated as one-dose -- the
# person-time ratio 162196/(162196+323558) from Butler Table 1.
#
# That weight is NOT exposed as a control, deliberately. Person-time in an
# intermediate dose state is not the share of children who stop there: it is
# accrued mostly by children passing through one dose on the way to completing
# the series, so its relationship to the quantity we want is unclear in both
# size and direction. Rather than offer a knob whose calibration we cannot
# defend, the app takes the published figures as given. The assumption cannot
# affect any excess estimate in any case -- both partial levels are held fixed
# between the two columns, so their contribution cancels in the difference; it
# moves only the baseline, by about 5% across the full range of the weight.
#
# The partially vaccinated row carries NA bounds deliberately. Its risk is a
# mixture of two estimates, and averaging two confidence limits does not yield a
# confidence limit for the mixture. The sensitivity analysis that matters uses
# `rv_rd_bounds()` on the fully vaccinated contrast instead.

rv_groups <- function() {
  data.frame(
    id        = c("unvax", "partial", "full"),
    label     = c("Unvaccinated", "Partially vaccinated", "Fully vaccinated"),
    share     = c(13.9, 15.3, 70.7),
    risk_h    = c(0.88, 0.67, 0.47),
    risk_e    = c(4.36, 4.34, 3.15),
    risk_h_lo = c(0.79, NA, 0.45),
    risk_h_hi = c(0.97, NA, 0.49),
    risk_e_lo = c(4.17, NA, 3.09),
    risk_e_hi = c(4.57, NA, 3.21),
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
    # Costs are whole dollars, by decision: the sliders step by $1 and the
    # defaults are rounded to match. The defaults MUST stay whole numbers.
    # ionRangeSlider rounds a value to the decimal count implied by `step`, so a
    # fractional default against step = 1 would display and return the rounded
    # figure while the model held the exact one -- the app would disagree with
    # itself, and a reset would silently change the answer. Keeping default and
    # step on the same grid is what prevents that.
    #
    # Karve's CPI-inflated figures are 19251.56 and 781.83. Rounding them, with
    # the indirect cost below, puts this model $62,330 above the spreadsheet's
    # baseline and 0.008% above its excess figures. Nothing the letter reports
    # moves: both printed figures stay $34.5M and $103.5M, and footnote d stays
    # 6.3% and 18.8%. The Spreadsheet equivalence block in test-model.R restores
    # all three unrounded values and confirms the cells still reproduce.
    s("c_hosp", "Direct medical cost per AGE-related hospitalization ($)",
      19252, 0, 60000, 1, 14439, 24064,
      "Karve et al. 2014, CPI-inflated to Jan 2025 ($19,251.56), to the dollar",
      "slider"),
    s("c_ed", "Direct medical cost per AGE-related ED visit ($)",
      782, 0, 4000, 1, 586, 977,
      "Karve et al. 2014, CPI-inflated to Jan 2025 ($781.83), to the dollar",
      "slider"),
    # Spreadsheet "Indirect costs" cell N45 = H45 + P24, i.e. two days of
    # $1,117 weekly earnings taken over a 7-day week, plus $104.64 of median
    # out-of-pocket costs: 1117 / 7 * 2 + 104.64 = 423.782857142857...
    #
    # Rounded to $424 with the other two. The repeating decimal is an unrounded
    # Excel intermediate rather than a chosen figure -- 7 does not divide 1117 --
    # so there was never a cost of $423.782857142857 to preserve.
    s("c_indirect", "Indirect (productivity) cost per episode ($)",
      424, 0, 2000, 1, 318, 530,
      paste("2 days of median weekly earnings (BLS CPS 2023, $1,117/wk over a",
            "7-day week) plus $104.64 median out-of-pocket costs, to the",
            "dollar; applied identically to ED and inpatient episodes"),
      "slider")
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
# `point` is derived from the published risks rather than transcribed from the
# risk-difference column, so that applying it restores the app's defaults
# exactly. The two disagree by 0.01 in each direction: differencing the rounded
# risks gives -0.41 and -1.21, while the paper's column reports -0.40 and -1.22.
# Both are rounded views of the same unrounded quantity, but only the former
# reproduces the letter -- taking -0.40 would put the full-series risk at 0.48
# rather than the published 0.47. Deriving it also keeps all three bounds on one
# basis: every one of them is "risk in the unvaccinated, plus this difference".

rv_rd_bounds <- function() {
  g <- rv_groups()
  n <- nrow(g)
  list(
    lower = c(hosp = -0.50, ed = -1.43),   # larger protective effect
    point = c(hosp = g$risk_h[n] - g$risk_h[1],
              ed   = g$risk_e[n] - g$risk_e[1]),
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


# --- Constraint: vaccination cannot increase risk -----------------------------
# A vaccinated stratum carrying a HIGHER risk than the unvaccinated makes the
# projection incoherent rather than merely pessimistic: the excess turns
# negative, so the app would report that withdrawing vaccination prevents
# encounters. This caps every vaccinated stratum at the unvaccinated risk, for
# both outcomes.
#
# The constraint is applied to the inputs, not inside `rv_project()`, which
# stays a pure calculator. That keeps the algebraic identities the tests rely on
# intact and makes the capping visible as a property of the entered values.
#
# Note it can bind on published inputs. Butler et al. estimate the one-dose RV5
# two-year ED risk at 4.57% against 4.36% unvaccinated -- a point estimate in
# the harmful direction, with a confidence interval spanning no effect. The
# blended partial risk crosses 4.36% once the one-dose share passes 38.24%
# (4.23 + 0.34w = 4.36), so raising that weight above the published 33.39%
# eventually triggers the cap.

#' Cap every vaccinated stratum's risk at the unvaccinated risk
#'
#' @param groups Data frame shaped like `rv_groups()`; row 1 is the unvaccinated
#'   reference.
#' @return A list with `groups` (constrained) and `capped`, a character vector
#'   naming the cells that were altered -- empty when the constraint is inactive.
rv_clamp_harm <- function(groups) {
  if (nrow(groups) < 2) return(list(groups = groups, capped = character(0)))
  capped <- character(0)
  for (i in 2:nrow(groups)) {
    if (isTRUE(groups$risk_h[i] > groups$risk_h[1])) {
      capped <- c(capped, paste(groups$label[i], "hospitalization risk"))
      groups$risk_h[i] <- groups$risk_h[1]
    }
    if (isTRUE(groups$risk_e[i] > groups$risk_e[1])) {
      capped <- c(capped, paste(groups$label[i], "ED visit risk"))
      groups$risk_e[i] <- groups$risk_e[1]
    }
  }
  list(groups = groups, capped = capped)
}


# --- Published scenario columns -----------------------------------------------
# Derived from the current column rather than transcribed, so the two cannot
# drift apart. Matches spreadsheet rows J23-J26, J31-J34 and J41-J44: the shift
# moves percentage points from the full series into unvaccinated, holding the
# partially vaccinated stratum fixed.

rv_scenarios <- function() {
  base <- rv_groups()$share
  mk <- function(pp) {
    v <- base
    v[1] <- v[1] + pp
    v[length(v)] <- v[length(v)] - pp
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

# Strips a leading minus from a value that rounds to zero. Without this, an
# excess of -1e-14 -- which the no-harm cap routinely produces, since capping
# makes two risks equal and their difference lands a few ulp below zero --
# displays as "-0".
fmt_n <- function(x, digits = 0) {
  s <- formatC(x, format = "f", digits = digits, big.mark = ",")
  sub("^-(0(\\.0+)?)$", "\\1", s)
}
# Sign keys off the ROUNDED magnitude, so a value a few ulp below zero prints
# as "$0" rather than "-$0".
fmt_usd <- function(x) {
  n <- fmt_n(abs(x))
  paste0(ifelse(x < 0 & !grepl("^0(\\.0+)?$", n), "-$", "$"), n)
}

fmt_usd_short <- function(x) {
  s <- ifelse(x < 0, "-", "")
  a <- abs(x)
  ifelse(a >= 1e9, sprintf("%s$%.2fB", s, a / 1e9),
    ifelse(a >= 1e6, sprintf("%s$%.1fM", s, a / 1e6),
      ifelse(a >= 1e3, sprintf("%s$%.0fK", s, a / 1e3), sprintf("%s$%.0f", s, a))))
}
