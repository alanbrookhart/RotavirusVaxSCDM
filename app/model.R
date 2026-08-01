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
# Structure of the calculation, for each vaccination stratum s:
#
#   events_s = births * share_s * risk_s
#   cost     = sum_s(hosp_s) * unit_cost_hosp + sum_s(ed_s) * unit_cost_ed
#
# where risk_s is the 2-year cumulative incidence of the outcome from Butler et
# al. (Epidemiology 2021) and unit costs are per-episode costs in 2025 USD, taken
# either from a direct-medical or a societal (direct + indirect) perspective.
#
# The model is deterministic and accounts for direct effects of vaccination only;
# no indirect (herd) protection is assumed, consistent with the published letter.
# ------------------------------------------------------------------------------


# --- Parameter registry -------------------------------------------------------
# One row per varyable parameter. This table is the single source of truth: the
# app builds its sliders from it and the tornado analysis takes its low/high
# bounds from it. `low` and `high` are the published 95% confidence limits where
# available and plausible ranges otherwise (see `source` column).

rv_param_table <- function() {
  p <- function(id, label, group, default, min, max, step, low, high, source) {
    data.frame(
      id = id, label = label, group = group,
      default = default, min = min, max = max, step = step,
      low = low, high = high, source = source,
      stringsAsFactors = FALSE
    )
  }

  do.call(rbind, list(

    # -- Population ------------------------------------------------------------
    p("births", "Annual U.S. births", "Population",
      3622673, 3000000, 4200000, 1000,
      3441539, 3803807,
      "CDC Vital Statistics Rapid Release No. 38 (provisional 2024); range +/-5%"),

    # -- Uptake ----------------------------------------------------------------
    p("p_unvax", "Unvaccinated (%)", "Vaccination uptake",
      13.9, 0, 100, 0.1, 8.9, 18.9,
      "Sederdahl et al. Pediatrics 2019; range +/-5 percentage points"),
    p("p_partial", "Partially vaccinated (%)", "Vaccination uptake",
      15.3, 0, 100, 0.1, 10.3, 20.3,
      "Sederdahl et al. Pediatrics 2019; range +/-5 percentage points"),
    p("p_full", "Fully vaccinated (%)", "Vaccination uptake",
      70.7, 0, 100, 0.1, 65.7, 75.7,
      "Sederdahl et al. Pediatrics 2019; range +/-5 percentage points"),
    p("w_partial1", "Share of partially vaccinated with 1 dose (%)", "Vaccination uptake",
      33.39, 0, 100, 0.1, 20, 50,
      "Person-time split in Butler et al. 2021 Table 1: 162196/(162196+323558)"),

    # -- 2-year risk of AGE-related hospitalization, % -------------------------
    p("rh_unvax", "Hospitalization risk, unvaccinated (%)", "Hospitalization risk",
      0.88, 0, 3, 0.01, 0.79, 0.97,
      "Butler et al. 2021 Table 1 (95% CI)"),
    p("rh_p1", "Hospitalization risk, 1 dose RV5 (%)", "Hospitalization risk",
      0.80, 0, 3, 0.01, 0.62, 1.02,
      "Butler et al. 2021 Table 1 (95% CI)"),
    p("rh_p2", "Hospitalization risk, 2 doses RV5 (%)", "Hospitalization risk",
      0.61, 0, 3, 0.01, 0.52, 0.71,
      "Butler et al. 2021 Table 1 (95% CI)"),
    p("rh_full", "Hospitalization risk, full series (%)", "Hospitalization risk",
      0.47, 0, 3, 0.01, 0.45, 0.49,
      "Butler et al. 2021 Table 1 (95% CI)"),

    # -- 2-year risk of AGE-related ED visit, % --------------------------------
    p("re_unvax", "ED visit risk, unvaccinated (%)", "ED visit risk",
      4.36, 0, 12, 0.01, 4.17, 4.57,
      "Butler et al. 2021 Table 2 (95% CI)"),
    p("re_p1", "ED visit risk, 1 dose RV5 (%)", "ED visit risk",
      4.57, 0, 12, 0.01, 4.04, 5.16,
      "Butler et al. 2021 Table 2 (95% CI)"),
    p("re_p2", "ED visit risk, 2 doses RV5 (%)", "ED visit risk",
      4.23, 0, 12, 0.01, 3.95, 4.54,
      "Butler et al. 2021 Table 2 (95% CI)"),
    p("re_full", "ED visit risk, full series (%)", "ED visit risk",
      3.15, 0, 12, 0.01, 3.09, 3.21,
      "Butler et al. 2021 Table 2 (95% CI)"),

    # -- Unit costs, 2025 USD --------------------------------------------------
    p("c_hosp", "Direct medical cost per hospitalization ($)", "Unit costs",
      19251.56, 0, 60000, 10, 14438.67, 24064.45,
      "Karve et al. 2014, CPI-inflated to Jan 2025; range +/-25%"),
    p("c_ed", "Direct medical cost per ED visit ($)", "Unit costs",
      781.83, 0, 4000, 1, 586.37, 977.29,
      "Karve et al. 2014, CPI-inflated to Jan 2025; range +/-25%"),
    p("c_indirect", "Indirect (productivity) cost per episode ($)", "Unit costs",
      423.7829, 0, 2000, 1, 317.84, 529.73,
      paste("2 days of median weekly earnings (BLS CPS 2023, $1,117/wk) plus",
            "out-of-pocket costs; applied identically to ED and inpatient",
            "episodes; range +/-25%"))
  ))
}


# --- Defaults -----------------------------------------------------------------

rv_defaults <- function() {
  tab <- rv_param_table()
  stats::setNames(as.list(tab$default), tab$id)
}


#' Project AGE burden and cost under a given uptake distribution
#'
#' @param p        Named list of parameters (see `rv_param_table`). Percentages
#'                 are supplied on the 0-100 scale.
#' @param shift    Percentage points of the birth cohort moving from fully
#'                 vaccinated to unvaccinated. Clamped at the fully vaccinated
#'                 share.
#' @param societal If TRUE, unit costs include indirect (productivity) costs;
#'                 if FALSE, direct medical costs only.
#' @param cohorts  Number of consecutive annual birth cohorts. Estimates are
#'                 additive across cohorts, so this is a simple multiplier.
#' @param normalize If TRUE, uptake shares are rescaled to sum to 100%. The
#'                 published shares sum to 99.9% because of rounding; leaving
#'                 this FALSE reproduces the spreadsheet exactly.
#'
#' @return A list with `strata` (per-stratum detail under both distributions),
#'   `baseline`, `scenario` and `excess` summaries.
rv_project <- function(p, shift = 0, societal = TRUE, cohorts = 1,
                       normalize = FALSE) {

  shares <- c(
    unvax = p$p_unvax,
    p1    = p$p_partial * p$w_partial1 / 100,
    p2    = p$p_partial * (1 - p$w_partial1 / 100),
    full  = p$p_full
  ) / 100

  if (normalize && sum(shares) > 0) shares <- shares / sum(shares)

  # Shift moves people from the fully vaccinated stratum into the unvaccinated
  # stratum; partially vaccinated strata are untouched, as in the spreadsheet.
  shift_eff <- min(shift / 100, shares[["full"]])
  shares_s <- shares
  shares_s[["full"]]  <- shares_s[["full"]]  - shift_eff
  shares_s[["unvax"]] <- shares_s[["unvax"]] + shift_eff

  risk_h <- c(unvax = p$rh_unvax, p1 = p$rh_p1, p2 = p$rh_p2, p3 = p$rh_full) / 100
  risk_e <- c(unvax = p$re_unvax, p1 = p$re_p1, p2 = p$re_p2, p3 = p$re_full) / 100
  names(risk_h) <- names(risk_e) <- names(shares)

  unit_h <- p$c_hosp + if (isTRUE(societal)) p$c_indirect else 0
  unit_e <- p$c_ed   + if (isTRUE(societal)) p$c_indirect else 0

  summarise <- function(sh) {
    hosp <- p$births * sh * risk_h * cohorts
    ed   <- p$births * sh * risk_e * cohorts
    list(
      shares = sh,
      hosp = hosp, ed = ed,
      hosp_total = sum(hosp), ed_total = sum(ed),
      cost_hosp = sum(hosp) * unit_h,
      cost_ed   = sum(ed) * unit_e,
      cost_total = sum(hosp) * unit_h + sum(ed) * unit_e
    )
  }

  b <- summarise(shares)
  s <- summarise(shares_s)

  strata <- data.frame(
    stratum = c("Unvaccinated", "Partial RV5 (1 dose)",
                "Partial RV5 (2 doses)", "Full series"),
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
    shift_applied = 100 * shift_eff,
    share_sum = 100 * sum(shares),
    baseline = b,
    scenario = s,
    excess = list(
      hosp = s$hosp_total - b$hosp_total,
      ed   = s$ed_total - b$ed_total,
      cost_hosp = s$cost_hosp - b$cost_hosp,
      cost_ed   = s$cost_ed - b$cost_ed,
      cost_total = s$cost_total - b$cost_total,
      pct_hosp = 100 * (s$hosp_total - b$hosp_total) / b$hosp_total,
      pct_ed   = 100 * (s$ed_total - b$ed_total) / b$ed_total
    )
  )
}


#' Extract a single scalar outcome from a projection
rv_outcome <- function(res, outcome) {
  switch(outcome,
    excess_hosp = res$excess$hosp,
    excess_ed   = res$excess$ed,
    excess_cost = res$excess$cost_total,
    total_hosp  = res$scenario$hosp_total,
    total_ed    = res$scenario$ed_total,
    total_cost  = res$scenario$cost_total,
    stop("Unknown outcome: ", outcome)
  )
}

rv_outcome_choices <- c(
  "Excess hospitalizations"      = "excess_hosp",
  "Excess ED visits"             = "excess_ed",
  "Excess expenditures ($)"      = "excess_cost",
  "Total hospitalizations"       = "total_hosp",
  "Total ED visits"              = "total_ed",
  "Total expenditures ($)"       = "total_cost"
)


#' One-way sensitivity analysis over a single parameter
#'
#' @param param_id Parameter to vary.
#' @param values   Values to evaluate; defaults to a 41-point grid spanning the
#'                 parameter's low/high bounds.
rv_oneway <- function(p, param_id, outcome = "excess_cost", shift = 10,
                      societal = TRUE, cohorts = 1, normalize = FALSE,
                      values = NULL, n = 41) {
  tab <- rv_param_table()
  row <- tab[tab$id == param_id, ]
  if (is.null(values)) values <- seq(row$low, row$high, length.out = n)

  y <- vapply(values, function(v) {
    pp <- p
    pp[[param_id]] <- v
    rv_outcome(rv_project(pp, shift, societal, cohorts, normalize), outcome)
  }, numeric(1))

  data.frame(value = values, outcome = y)
}


#' Tornado analysis: influence of each parameter at its low/high bound
rv_tornado <- function(p, outcome = "excess_cost", shift = 10, societal = TRUE,
                       cohorts = 1, normalize = FALSE, param_ids = NULL) {
  tab <- rv_param_table()
  if (!is.null(param_ids)) tab <- tab[tab$id %in% param_ids, ]

  base <- rv_outcome(rv_project(p, shift, societal, cohorts, normalize), outcome)

  eval_at <- function(id, v) {
    pp <- p; pp[[id]] <- v
    rv_outcome(rv_project(pp, shift, societal, cohorts, normalize), outcome)
  }

  out <- data.frame(
    id = tab$id,
    label = tab$label,
    group = tab$group,
    low_value = tab$low,
    high_value = tab$high,
    at_low = vapply(seq_len(nrow(tab)), function(i) eval_at(tab$id[i], tab$low[i]), numeric(1)),
    at_high = vapply(seq_len(nrow(tab)), function(i) eval_at(tab$id[i], tab$high[i]), numeric(1)),
    stringsAsFactors = FALSE
  )
  out$base <- base
  out$lower <- pmin(out$at_low, out$at_high)
  out$upper <- pmax(out$at_low, out$at_high)
  out$swing <- out$upper - out$lower
  out[order(out$swing), ]
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
