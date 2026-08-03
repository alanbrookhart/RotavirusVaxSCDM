# Manual-Entry Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app's slider-and-shift machinery with a typed grid where the reader enters the uptake percentages and risk rates for each vaccination group directly, and cut the app to a single-screen calculator.

**Architecture:** `model.R` splits its one parameter registry into `rv_groups()` (the typed grid), `rv_scalars()` (remaining sliders) and `rv_scenarios()` (prefill columns). `rv_project()` stops deriving a scenario from a `shift` and instead receives both share vectors. `app.R` drops from four tabs to two, with a hand-built HTML table of `numericInput`s as the primary control.

**Tech Stack:** R 4.3.2, shiny 1.10.0, bslib 0.9.0, base graphics. Deployed as a static Shinylive (webR) site.

## Global Constraints

- **No new package dependencies.** `app.R` may use only `shiny` and `bslib`; plots use base graphics. Anything else adds wasm packages to an already 30–40 MB Shinylive bundle.
- **The regression suite is the gate.** `Rscript tests/test-model.R` must pass before any commit; `build.R` sources it and CI runs it.
- **All commands run from the repository root**, `/Users/ab771/Dropbox/work/duke/projects/RotaSCDMJAMA`.
- **Reproduction targets are exact spreadsheet cells** from `docs/RV spreadsheet.xlsx`, sheet `Butler et al RV Tables`: `K19` = 20201.714152, `K60` = 126708.413902, `W23` = 550236945.15, `X24` = 34508431.45, `X25` = 69016862.91, `X26` = 103525294.36.
- **Never round a derived constant into a literal.** Write it as its expression. Two rounded constants broke this suite on 2026-08-02.
- **Fractional defaults must be verified in a real browser**, not only in `testServer`. A value that survives the test but snaps to a slider's `step` grid would make the app disagree with its own passing suite.
- **Commit as Alan Brookhart. Never add a `Co-Authored-By: Claude` trailer.**

---

### Task 1: Model API — registries, `rv_project()`, and the regression suite

**Files:**
- Modify: `app/model.R` (full rewrite of the registry and projection sections; keep the formatting helpers at the end)
- Modify: `tests/test-model.R` (full rewrite)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces, relied on by Tasks 2 and 3:
  - `rv_groups()` → data.frame, 4 rows, columns `id` (chr), `label` (chr), `share` (dbl, percent), `risk_h` (dbl, percent), `risk_e` (dbl, percent), `risk_h_lo`, `risk_h_hi`, `risk_e_lo`, `risk_e_hi` (dbl, percent).
  - `rv_scalars()` → data.frame, 4 rows, columns `id`, `label`, `default`, `min`, `max`, `step`, `low`, `high`, `source`.
  - `rv_scalar_defaults()` → named list of the four scalar defaults.
  - `rv_scenarios()` → named list `"10%"`, `"20%"`, `"30%"`, each a length-4 numeric of scenario shares in group order.
  - `rv_project(groups, scen_share, scalars, societal = TRUE, cohorts = 1)` → list with `strata`, `unit_cost_hosp`, `unit_cost_ed`, `share_sum_base`, `share_sum_scen`, `baseline`, `scenario`, `excess`. `excess` has `hosp`, `ed`, `cost_hosp`, `cost_ed`, `cost_total`, `pct_hosp`, `pct_ed`, `pct_cost`.
  - `rv_num(x, default)` → scalar numeric. `NULL` yields `default` (input not yet initialised); `NA`/non-finite/wrong-length yields `0` (user cleared the box).
  - Unchanged and still exported: `fmt_n()`, `fmt_usd()`, `fmt_usd_short()`, `%||%`.

- [ ] **Step 1: Write the failing test**

Replace the entire contents of `tests/test-model.R` with:

```r
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Rscript tests/test-model.R`

Expected: FAIL with `could not find function "rv_groups"`.

- [ ] **Step 3: Rewrite the model**

In `app/model.R`, replace everything from the `# --- Parameter registry` comment down to and including the closing brace of `rv_tornado()` with the following. Keep the file header comment block (updating the description of the calculation) and keep the `# --- Small utilities` and `# --- Formatting helpers` sections at the end exactly as they are.

```r
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
  s <- function(id, label, default, min, max, step, low, high, source) {
    data.frame(id = id, label = label, default = default,
      min = min, max = max, step = step, low = low, high = high,
      source = source, stringsAsFactors = FALSE)
  }

  do.call(rbind, list(
    s("births", "Annual U.S. births",
      3622673, 3000000, 4200000, 1000, 3441539, 3803807,
      "CDC Vital Statistics Rapid Release No. 38 (provisional 2024); range +/-5%"),
    s("c_hosp", "Direct medical cost per hospitalization ($)",
      19251.56, 0, 60000, 10, 14438.67, 24064.45,
      "Karve et al. 2014, CPI-inflated to Jan 2025; range +/-25%"),
    s("c_ed", "Direct medical cost per ED visit ($)",
      781.83, 0, 4000, 1, 586.37, 977.29,
      "Karve et al. 2014, CPI-inflated to Jan 2025; range +/-25%"),
    # Kept as the underlying expression (spreadsheet "Indirect costs" cell
    # N45 = H45 + P24): $1,117 weekly earnings over a 7-day week, two days of
    # it, plus $104.64 of median out-of-pocket costs.
    s("c_indirect", "Indirect (productivity) cost per episode ($)",
      1117 / 7 * 2 + 104.64, 0, 2000, 1, 317.84, 529.73,
      paste("2 days of median weekly earnings (BLS CPS 2023, $1,117/wk) plus",
            "out-of-pocket costs; applied identically to ED and inpatient",
            "episodes; range +/-25%"))
  ))
}


rv_scalar_defaults <- function() {
  tab <- rv_scalars()
  stats::setNames(as.list(tab$default), tab$id)
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Rscript tests/test-model.R`

Expected: every line ends `OK`, then `All checks passed.`

In particular `Total expenditures (xlsx W23)` must read
`550236944.7205  vs  550236945.1500  OK` — the six-decimal split lands $0.43
*below* the spreadsheet, inside the $1 tolerance. If that line shows a
materially different figure, the shares in `rv_groups()` are wrong; do not widen
the tolerance to make it pass.

- [ ] **Step 5: Confirm the dead functions are gone**

Run: `grep -nE 'rv_oneway|rv_tornado|rv_outcome' app/model.R`

Expected: no output. (`app/app.R` will still match; that is fixed in Task 2.)

- [ ] **Step 6: Commit**

```bash
git add app/model.R tests/test-model.R
git commit -m "refactor(model): take explicit scenario shares instead of a derived shift"
```

---

### Task 2: Calculator UI — the typed grid and the two-tab shell

**Files:**
- Modify: `app/app.R` (rewrite of the UI and server; the `plot_counts` renderer and the "Model & sources" prose carry over)

**Interfaces:**
- Consumes: everything in Task 1's Produces block.
- Produces, relied on by Task 3: input ids `cur_<id>`, `scen_<id>`, `rh_<id>`, `re_<id>` for each of the four group ids (`unvax`, `p1`, `p2`, `full`); reactives `gvals()` (a `rv_groups()`-shaped data frame reflecting current inputs), `scen_share()` (length-4 numeric), `res()` (an `rv_project()` result); output slots `sum_cur` and `sum_scen` as `uiOutput`; the `#grid-wrap` container.

- [ ] **Step 1: Replace the header, constants and CSS**

In `app/app.R`, replace the `PARAMS`/`DEFAULTS`/`GROUPS` constants and the `param_slider`/`param_panel` helpers with:

```r
GROUPS  <- rv_groups()
SCALARS <- rv_scalars()
SCEN    <- rv_scenarios()

# Scenario column opens on the published 10% scenario, so the app loads showing
# the letter's headline result rather than an all-zero excess.
SCEN_DEFAULT <- SCEN[["10%"]]

PAL <- list(
  base   = "#94a3b8",
  excess = "#b91c1c",
  hosp   = "#1e40af",
  ed     = "#0e7490",
  grid   = "#e2e8f0",
  text   = "#1f2937"
)

# One editable cell. The grid's header row supplies the labelling, so each
# numericInput carries no label of its own.
grid_cell <- function(id, value, step) {
  tags$td(numericInput(id, label = NULL, value = value, step = step,
    width = "100%"))
}

group_grid <- function() {
  rows <- lapply(seq_len(nrow(GROUPS)), function(i) {
    g <- GROUPS[i, ]
    tags$tr(
      tags$th(g$label, scope = "row", class = "grid-label"),
      grid_cell(paste0("cur_",  g$id), g$share,          0.1),
      grid_cell(paste0("scen_", g$id), SCEN_DEFAULT[i],  0.1),
      grid_cell(paste0("rh_",   g$id), g$risk_h,         0.01),
      grid_cell(paste0("re_",   g$id), g$risk_e,         0.01)
    )
  })

  tags$table(class = "table grid-table align-middle mb-1",
    tags$thead(tags$tr(
      tags$th("Vaccination group", style = "width: 30%;"),
      tags$th("Current %"), tags$th("Scenario %"),
      tags$th("Hosp. risk %"), tags$th("ED risk %")
    )),
    tags$tbody(rows),
    tags$tfoot(tags$tr(
      tags$th(""),
      tags$td(uiOutput("sum_cur")),
      tags$td(uiOutput("sum_scen")),
      tags$td(""), tags$td("")
    ))
  )
}

scalar_slider <- function(row) {
  tags$div(
    title = row$source,
    sliderInput(row$id, row$label, min = row$min, max = row$max,
      value = row$default, step = row$step, ticks = FALSE, width = "100%")
  )
}
```

Then extend the CSS block in `header = tags$head(tags$style(HTML(...)))` by appending these rules to the existing ones:

```css
.grid-table td .form-group,
.grid-table td .shiny-input-container { margin-bottom: 0; width: 100% !important; }
.grid-table th { font-size: .82rem; font-weight: 600; vertical-align: bottom; }
.grid-table .grid-label { font-weight: 500; font-size: .9rem; white-space: nowrap; }
.grid-table tfoot td { padding-top: .1rem; }
.grid-sum { font-size: .82rem; color: #64748b; }
.grid-sum.warn { color: #b45309; font-weight: 600; }
```

- [ ] **Step 2: Replace the UI**

Replace the whole `ui <- page_navbar(...)` call's `sidebar` and its four `nav_panel`s. The sidebar becomes:

```r
  sidebar = sidebar(
    width = 340,
    open = "open",

    h6("Cost perspective", class = "text-uppercase text-muted mb-1"),
    radioButtons("perspective", NULL,
      choices = c("Societal (direct + indirect)" = "societal",
                  "Direct medical only" = "direct"),
      selected = "societal"),

    numericInput("cohorts", "Number of annual birth cohorts",
      value = 1, min = 1, max = 20, step = 1),

    hr(),
    h6("Population and costs", class = "text-uppercase text-muted mb-1"),
    lapply(seq_len(nrow(SCALARS)), function(i) scalar_slider(SCALARS[i, ])),

    actionButton("reset", "Reset to published values",
      class = "btn-outline-secondary btn-sm mt-2")
  ),
```

The first `nav_panel` becomes:

```r
  nav_panel(
    "Calculator",
    card(
      card_header("Vaccination groups"),
      card_body(
        div(id = "grid-wrap", group_grid()),
        div(class = "d-flex gap-2 align-items-center mt-2",
          span(class = "small text-muted me-1", "Fill scenario column:"),
          actionButton("fill_10", "10%", class = "btn-outline-primary btn-sm"),
          actionButton("fill_20", "20%", class = "btn-outline-primary btn-sm"),
          actionButton("fill_30", "30%", class = "btn-outline-primary btn-sm")
        )
      )
    ),
    uiOutput("warn"),
    layout_columns(
      col_widths = c(4, 4, 4),
      value_box("Excess hospitalizations", textOutput("vb_hosp"), theme = "primary"),
      value_box("Excess ED visits", textOutput("vb_ed"), theme = "secondary"),
      value_box("Excess expenditures", textOutput("vb_cost"), theme = "danger")
    ),
    card(
      card_header("Encounters per annual birth cohort, to age 2 years"),
      plotOutput("plot_counts", height = "330px")
    ),
    card(
      card_header("Detail by vaccination stratum"),
      tableOutput("tbl_strata")
    ),
    card(
      card_header("Summary"),
      tableOutput("tbl_summary")
    )
  ),
```

Delete the `"One-way sensitivity"` and `"Tornado"` nav panels entirely. Keep the `"Model & sources"` panel, with two edits to its prose: in the "How the projection works" markdown, replace the paragraph beginning "The scenario moves a specified share" with

```
The Current and Scenario columns are entered directly. Any pair of distributions
can be compared; the 10%, 20% and 30% buttons fill the Scenario column with the
published scenarios, which move that many percentage points from the fully
vaccinated stratum into the unvaccinated one while holding the partially
vaccinated strata fixed.
```

and in the "Reproducibility check" markdown, replace the first paragraph with

```
At published values with the 10% scenario, the app reproduces the accompanying
spreadsheet: 20,202 baseline hospitalizations and 126,708 baseline ED visits, and
an excess of 1,485 hospitalizations and 4,383 ED visits.
```

- [ ] **Step 3: Replace the server's reactives and outputs**

Replace the `pars()`, `societal()`, `cohorts()` and `res()` reactives with:

```r
  gvals <- reactive({
    g <- GROUPS
    g$share  <- vapply(GROUPS$id, function(i)
      rv_num(input[[paste0("cur_", i)]], GROUPS$share[GROUPS$id == i]), numeric(1))
    g$risk_h <- vapply(GROUPS$id, function(i)
      rv_num(input[[paste0("rh_", i)]], GROUPS$risk_h[GROUPS$id == i]), numeric(1))
    g$risk_e <- vapply(GROUPS$id, function(i)
      rv_num(input[[paste0("re_", i)]], GROUPS$risk_e[GROUPS$id == i]), numeric(1))
    g
  })

  scen_share <- reactive({
    vapply(seq_len(nrow(GROUPS)), function(i)
      rv_num(input[[paste0("scen_", GROUPS$id[i])]], SCEN_DEFAULT[i]), numeric(1))
  })

  scalars <- reactive({
    v <- rv_scalar_defaults()
    for (id in SCALARS$id) {
      if (!is.null(input[[id]])) {
        v[[id]] <- rv_num(input[[id]], v[[id]])
      }
    }
    v
  })

  societal <- reactive(identical(input$perspective, "societal"))
  cohorts  <- reactive(max(1, rv_num(input$cohorts, 1)))

  res <- reactive({
    rv_project(gvals(), scen_share(), scalars(),
      societal = societal(), cohorts = cohorts())
  })
```

Delete the `plot_shift`, `plot_oneway`, `plot_tornado`, `ow_note`, `tbl_tornado` and `tor` definitions, and the `output$tbl_sources` renderer's dependence on `PARAMS` — rewrite that last one as:

```r
  output$tbl_sources <- renderTable({
    num <- function(x) formatC(x, format = "fg", digits = 8, big.mark = ",")
    g <- GROUPS
    rbind(
      data.frame(
        Parameter = c(paste("Share,", g$label),
                      paste("Hospitalization risk,", g$label),
                      paste("ED visit risk,", g$label)),
        `Published value` = num(c(g$share, g$risk_h, g$risk_e)),
        Source = c(rep("Sederdahl et al. Pediatrics 2019; partial split from Butler et al. 2021 Table 1", 4),
                   rep("Butler et al. 2021 Table 1", 4),
                   rep("Butler et al. 2021 Table 2", 4)),
        check.names = FALSE, stringsAsFactors = FALSE),
      data.frame(
        Parameter = SCALARS$label,
        `Published value` = num(SCALARS$default),
        Source = SCALARS$source,
        check.names = FALSE, stringsAsFactors = FALSE)
    )
  }, align = "lrl", width = "100%", spacing = "xs")
```

Add `pct_cost` to the summary table's `Relative excess` column by replacing that vector with:

```r
      `Relative excess` = c(sprintf("%+.1f%%", r$excess$pct_hosp),
        sprintf("%+.1f%%", r$excess$pct_ed), "", "",
        sprintf("%+.1f%%", r$excess$pct_cost), "", ""),
```

- [ ] **Step 4: Verify the app loads and reproduces the published figures**

Run:

```bash
Rscript -e 'suppressMessages(library(shiny)); shiny::testServer(shinyAppFile("app/app.R"), { session$setInputs(perspective="societal", cohorts=1); cat("hosp:", output$vb_hosp, "| ed:", output$vb_ed, "| cost:", output$vb_cost, "\n"); invisible(output$tbl_strata); invisible(output$tbl_summary); invisible(output$tbl_sources); invisible(output$plot_counts); cat("all outputs render\n") })'
```

Expected: `hosp: 1,485 | ed: 4,383 | cost: $34.5M` then `all outputs render`. These are the defaults with the 10% scenario preloaded.

- [ ] **Step 5: Commit**

```bash
git add app/app.R
git commit -m "feat(app): typed group grid replaces uptake sliders and the shift control"
```

---

### Task 3: Prefill buttons, reset, column sums and blank-cell reporting

**Files:**
- Modify: `app/app.R` (server observers and the two sum outputs)

**Interfaces:**
- Consumes: Task 2's input ids, `gvals()`, `scen_share()`, and the `sum_cur`/`sum_scen` output slots.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the prefill and reset observers**

Add to the server, after the `res()` reactive:

```r
  # Prefill buttons. `local()` captures the scenario name per iteration; without
  # it every observer would close over the final value of `nm`.
  for (nm in names(SCEN)) local({
    scen_name <- nm
    btn <- paste0("fill_", sub("%", "", scen_name))
    observeEvent(input[[btn]], {
      v <- SCEN[[scen_name]]
      for (k in seq_len(nrow(GROUPS))) {
        updateNumericInput(session, paste0("scen_", GROUPS$id[k]), value = v[k])
      }
    }, ignoreInit = TRUE)
  })

  observeEvent(input$reset, {
    for (k in seq_len(nrow(GROUPS))) {
      updateNumericInput(session, paste0("cur_",  GROUPS$id[k]), value = GROUPS$share[k])
      updateNumericInput(session, paste0("scen_", GROUPS$id[k]), value = SCEN_DEFAULT[k])
      updateNumericInput(session, paste0("rh_",   GROUPS$id[k]), value = GROUPS$risk_h[k])
      updateNumericInput(session, paste0("re_",   GROUPS$id[k]), value = GROUPS$risk_e[k])
    }
    for (i in seq_len(nrow(SCALARS))) {
      updateSliderInput(session, SCALARS$id[i], value = SCALARS$default[i])
    }
    updateRadioButtons(session, "perspective", selected = "societal")
    updateNumericInput(session, "cohorts", value = 1)
  })
```

- [ ] **Step 2: Add the column-sum readouts**

```r
  sum_badge <- function(total) {
    off <- abs(total - 100) > 0.05
    span(class = paste("grid-sum", if (off) "warn" else ""),
      sprintf("sums to %.1f%%", total))
  }

  output$sum_cur  <- renderUI(sum_badge(sum(gvals()$share)))
  output$sum_scen <- renderUI(sum_badge(sum(scen_share())))
```

- [ ] **Step 3: Replace the warning banner with blank-cell reporting**

Replace the existing `output$warn` renderer with:

```r
  # Cell id -> human label, for naming blanks in the banner.
  CELL_LABELS <- local({
    prefixes <- c(cur = "current %", scen = "scenario %",
                  rh = "hospitalization risk", re = "ED risk")
    ids <- character(0); labs <- character(0)
    for (p in names(prefixes)) {
      for (k in seq_len(nrow(GROUPS))) {
        ids  <- c(ids,  paste0(p, "_", GROUPS$id[k]))
        labs <- c(labs, paste0(GROUPS$label[k], " — ", prefixes[[p]]))
      }
    }
    stats::setNames(labs, ids)
  })

  output$warn <- renderUI({
    msgs <- list()

    blank <- names(CELL_LABELS)[vapply(names(CELL_LABELS), function(i) {
      v <- input[[i]]
      !is.null(v) && (length(v) != 1 || is.na(v))
    }, logical(1))]
    if (length(blank)) {
      msgs <- c(msgs, list(sprintf("Empty, treated as 0: %s.",
        paste(CELL_LABELS[blank], collapse = "; "))))
    }

    r <- res()
    for (nm in c("Current", "Scenario")) {
      tot <- if (nm == "Current") r$share_sum_base else r$share_sum_scen
      if (abs(tot - 100) > 0.05) {
        msgs <- c(msgs, list(sprintf(
          "%s shares sum to %.1f%%, not 100%%. The published values (13.9 / 15.3 / 70.7) sum to 99.9%% because of rounding; leaving this uncorrected reproduces the spreadsheet exactly.",
          nm, tot)))
      }
    }

    if (!length(msgs)) return(NULL)
    div(class = "alert alert-warning py-2 small", lapply(msgs, tags$div))
  })
```

- [ ] **Step 4: Verify the interactions**

Run:

```bash
Rscript -e 'suppressMessages(library(shiny)); shiny::testServer(shinyAppFile("app/app.R"), {
  session$setInputs(perspective="societal", cohorts=1)
  cat("default (10%):", output$vb_cost, "\n")
  session$setInputs(scen_unvax=43.9, scen_full=40.7)
  cat("typed 30%:    ", output$vb_cost, "\n")
  session$setInputs(scen_unvax=NA)
  cat("blank cell:   ", output$vb_cost, "\n")
  invisible(output$warn); invisible(output$plot_counts)
  cat("warn + plot render with a blank cell\n")
})'
```

Expected: `default (10%): $34.5M`, `typed 30%: $103.5M`, then a finite value for the blank case and `warn + plot render with a blank cell` — critically, no `need finite 'ylim' values` error.

- [ ] **Step 5: Verify in a real browser**

Fractional defaults must be confirmed against the live DOM, not just `testServer` — a value that snaps to a slider's `step` grid would make the app disagree with its passing test suite.

```bash
Rscript -e 'shiny::runApp("app", port=7817, host="127.0.0.1", launch.browser=FALSE)'
```

Open `http://127.0.0.1:7817`. Confirm all of:
- the `cur_p1` box reads `5.108756` and `c_indirect` reads `423.782857142857`;
- both footer sums read `sums to 99.9%` in amber;
- the Summary table's Total expenditures row reads `$550,236,945` baseline and `$34,508,431` excess;
- the Relative excess column shows `+7.4%`, `+3.5%` and `+6.3%`;
- clicking **30%** moves excess expenditures to `$103.5M` and the relative excess to `+18.8%`;
- clearing a Current cell shows the amber banner naming that cell, and no plot errors;
- **Reset** restores every cell.

- [ ] **Step 6: Run the full suite and commit**

```bash
Rscript tests/test-model.R
git add app/app.R
git commit -m "feat(app): scenario prefills, column-sum readout and blank-cell handling"
```

---

### Task 4: Documentation

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the final behaviour of Tasks 1–3.
- Produces: nothing.

- [ ] **Step 1: Update the repository layout and model sections**

In `README.md`, under "Repository layout", add these two lines after the `tests/` block:

```
design/
  specs/             Design documents
  plans/             Implementation plans
```

Replace the paragraph beginning "Two-year cumulative incidences come from Butler et al." through the end of "### Uptake can be specified two ways" with:

```markdown
Two-year cumulative incidences come from Butler et al. (*Epidemiology* 2021;32:598–606), estimated with inverse probability of censoring weighting in a commercially insured birth cohort.

### Entering a scenario

The Current and Scenario columns of the group grid are typed directly, so any pair of uptake distributions can be compared — including scenarios the published letter cannot express, such as children moving into partial vaccination rather than out of it altogether.

The **10%**, **20%** and **30%** buttons fill the Scenario column with the published scenarios, which move that many percentage points from the fully vaccinated stratum into the unvaccinated one while holding the partially vaccinated strata fixed. Because only two strata move and the risks are constants, the excess is exactly linear in the shift magnitude.

The published shares (13.9% unvaccinated, 15.3% partially vaccinated, 70.7% fully vaccinated) sum to 99.9% because of rounding. The app reports each column's sum but does not correct it: auto-normalising would leave the app unable to reproduce the letter.

The partially vaccinated 15.3% is split into one- and two-dose RV5 recipients at the person-time ratio in Butler et al. Table 1, shown to six decimals as 5.108756% and 10.191244%. That rounding lands within $0.43 of the spreadsheet's baseline expenditure; carrying fewer digits would cost materially more.
```

- [ ] **Step 2: Update the Verification and Parameter sources sections**

Replace the Verification table's caption sentence with:

```markdown
`tests/test-model.R` checks the R implementation against specific cells of `docs/RV spreadsheet.xlsx`. All six primary targets reproduce to within $1:
```

In the "Parameter sources" table, replace the `Uptake distribution` and `Indirect cost per episode` rows with:

```markdown
| Uptake distribution | 13.9 / 5.108756 / 10.191244 / 70.7 % | Sederdahl et al. *Pediatrics* 2019; partial split from Butler et al. 2021 Table 1 |
```

and

```markdown
| Indirect cost per episode | \$423.782857 | Two days of median weekly earnings (BLS CPS 2023, $1,117/wk over a 7-day week) plus $104.64 median out-of-pocket costs |
```

Delete the sentence beginning "Tornado bounds use published 95% confidence limits", and replace it with:

```markdown
The published 95% confidence limits are retained in `rv_groups()` and `rv_scalars()` as `_lo`/`_hi` columns. Nothing consumes them yet; they are the input for the sensitivity analysis planned as follow-up work.
```

- [ ] **Step 3: Update Possible extensions**

Replace the three bullets under "Possible extensions" with:

```markdown
- **Sensitivity analysis.** The agreed next piece of work, and the answer to Reviewer #3's request that uncertainty be incorporated into the projections. The confidence limits it needs are already carried in `rv_groups()` and `rv_scalars()`. Note that the bootstrap confidence intervals in Butler et al. are marginal, so treating the four stratum-specific risks as independent will overstate the width of any resulting interval.
- **Indirect (herd) protection.** A multiplier on risk in the unvaccinated stratum, addressing the first stated limitation. Whether this widens or narrows the excess depends on whether the multiplier is held fixed or allowed to scale with coverage, which is the substantively interesting question.
```

- [ ] **Step 4: Verify the README's claims still hold**

Run: `Rscript tests/test-model.R`

Expected: `All checks passed.` Confirm by eye that each figure in the README's Verification table appears in the test output.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: describe the typed group grid and the retained CI bounds"
```

---

## Self-Review

**Spec coverage.** Every section of the design maps to a task: the model API and default tables to Task 1; the two-tab shell, grid, and sidebar to Task 2; validation, prefills and blank handling to Task 3; the documented consequences to Task 4. The retained `low`/`high` bounds appear in Task 1's `rv_groups()`/`rv_scalars()` and are described in Task 4. The removal of `plot_shift` is in Task 2 Step 3. The precision decision is in Task 1's `rv_groups()` and the browser check in Task 3 Step 5.

**Placeholder scan.** No TBD, TODO, "similar to Task N", or "add appropriate error handling". Every code step carries its code.

**Type consistency.** `rv_project(groups, scen_share, scalars, societal, cohorts)` is called with that signature in Task 1's tests and Task 2's `res()`. `rv_num(x, default)` is used consistently in both. `SCEN_DEFAULT` is defined in Task 2 Step 1 and used in Tasks 2 and 3. Input id patterns `cur_`/`scen_`/`rh_`/`re_` are identical across Tasks 2 and 3. `share_sum_base`/`share_sum_scen` are produced in Task 1 and consumed in Task 3.
