# ------------------------------------------------------------------------------
# Rotavirus SCDM Sensitivity Analysis
#
# Interactive sensitivity analysis for the projected burden of AGE-related
# healthcare encounters and expenditures following a shift from a routine to a
# shared clinical decision-making (SCDM) rotavirus vaccination recommendation.
#
# Companion to: Butler AM, Panozzo CA, Boutzoukas AE, Brookhart MA.
#   "Rotavirus Vaccination: Impact of New Recommendation."
#
# Runs in the browser via Shinylive (webR); depends only on shiny and bslib,
# both of which ship with the Shinylive runtime. All plotting uses base
# graphics, so no additional wasm packages are downloaded.
# ------------------------------------------------------------------------------

library(shiny)
library(bslib)

# Sourced (not local) so that model objects are visible to both ui and server
# under Shinylive as well as under a conventional Shiny server.
source("model.R")

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


# --- UI -----------------------------------------------------------------------

ui <- page_navbar(
  title = "Rotavirus SCDM: Sensitivity Analysis",
  # A stock Bootstrap 5 theme is used deliberately: custom bs_theme() arguments
  # trigger Sass compilation, which is slow inside webR. Tweaks go in CSS below.
  theme = bs_theme(version = 5),
  fillable = FALSE,

  header = tags$head(tags$style(HTML("
    body { font-size: 0.94rem; }
    .value-box .value-box-title { font-size: 0.82rem; text-transform: uppercase;
      letter-spacing: .04em; opacity: .85; }
    .card-header { font-weight: 600; }
    table { font-variant-numeric: tabular-nums; }
    .irs--shiny .irs-bar, .irs--shiny .irs-single { background: #1e40af; border-color: #1e40af; }
    .accordion-button { font-weight: 600; font-size: 0.88rem; }
    .form-group { margin-bottom: .6rem; }
    .grid-table td .form-group,
    .grid-table td .shiny-input-container { margin-bottom: 0; width: 100% !important; }
    .grid-table th { font-size: .82rem; font-weight: 600; vertical-align: bottom; }
    .grid-table .grid-label { font-weight: 500; font-size: .9rem; white-space: nowrap; }
    .grid-table tfoot td { padding-top: .1rem; }
    .grid-sum { font-size: .82rem; color: #64748b; }
    .grid-sum.warn { color: #b45309; font-weight: 600; }
  "))),

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

  # -- Calculator ----------------------------------------------------------
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

  # -- Notes -------------------------------------------------------------------
  nav_panel(
    "Model & sources",
    card(
      card_header("How the projection works"),
      card_body(
        markdown(
"For each vaccination stratum *s* the model computes

```
encounters_s = births x share_s x two_year_risk_s
cost         = sum(hospitalizations) x unit_cost_hosp
             + sum(ED visits)        x unit_cost_ED
```

Two-year cumulative incidences of AGE-related hospitalization and emergency
department visits come from Butler et al. (*Epidemiology* 2021), estimated with
inverse probability of censoring weighting in a commercially insured birth cohort.
Unit costs are per-episode costs in January 2025 USD; the societal perspective
adds an indirect cost, applied identically to inpatient and ED episodes,
representing two days of median weekly earnings plus out-of-pocket costs.

The Current and Scenario columns are entered directly. Any pair of distributions
can be compared; the 10%, 20% and 30% buttons fill the Scenario column with the
published scenarios, which move that many percentage points from the fully
vaccinated stratum into the unvaccinated one while holding the partially
vaccinated strata fixed.

Estimates account for direct effects of vaccination only. No indirect (herd)
protection is assumed, so projected excess encounters should be read as a lower
bound: indirect protection reduces rotavirus burden in unvaccinated children,
but declining coverage would erode that protection as well, and the net direction
of the bias depends on how strongly transmission responds to coverage. The
projection is also restricted to children under two years and relies on
AGE-coded encounters, which have imperfect sensitivity."
        )
      )
    ),
    card(
      card_header("Parameter sources"),
      tableOutput("tbl_sources")
    ),
    card(
      card_header("Reproducibility check"),
      card_body(
        markdown(
"At published values with the 10% scenario, the app reproduces the accompanying
spreadsheet: 20,202 baseline hospitalizations and 126,708 baseline ED visits, and
an excess of 1,485 hospitalizations and 4,383 ED visits.

Note that the published letter reports \\$32.0 million for the 10% shift and
\\$103.5 million for the 30% shift. These are not on the same footing: \\$32.0
million is the excess under a **direct medical** perspective, whereas \\$103.5
million is the excess under a **societal** perspective. The societal figure for
a 10% shift is \\$34.5 million, and the direct-medical figure for a 30% shift is
\\$96.1 million. Switching the cost perspective in the sidebar reproduces either
convention."
        )
      )
    )
  ),

  nav_spacer(),
  nav_item(tags$a("Source", href = "https://github.com/", target = "_blank"))
)


# --- Server -------------------------------------------------------------------

server <- function(input, output, session) {

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

  sum_badge <- function(total) {
    off <- abs(total - 100) > 0.05
    span(class = paste("grid-sum", if (off) "warn" else ""),
      sprintf("sums to %.1f%%", total))
  }

  output$sum_cur  <- renderUI(sum_badge(sum(gvals()$share)))
  output$sum_scen <- renderUI(sum_badge(sum(scen_share())))

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

  # -- Value boxes -------------------------------------------------------------
  output$vb_hosp <- renderText(fmt_n(res()$excess$hosp))
  output$vb_ed   <- renderText(fmt_n(res()$excess$ed))
  output$vb_cost <- renderText(fmt_usd_short(res()$excess$cost_total))

  # -- Counts plot -------------------------------------------------------------
  output$plot_counts <- renderPlot({
    r <- res()
    m <- rbind(
      Baseline = c(r$baseline$hosp_total, r$baseline$ed_total),
      Scenario = c(r$scenario$hosp_total, r$scenario$ed_total)
    )
    op <- par(mfrow = c(1, 2), mar = c(4, 5, 3, 1), las = 1, bty = "n",
              col.axis = PAL$text, col.lab = PAL$text)
    on.exit(par(op))
    for (j in 1:2) {
      lab <- c("Hospitalizations", "ED visits")[j]
      v <- m[, j]
      bp <- barplot(v, col = c(PAL$base, if (j == 1) PAL$hosp else PAL$ed),
        border = NA, main = lab, ylim = c(0, max(v) * 1.18),
        yaxt = "n", cex.main = 1.1)
      axis(2, at = pretty(c(0, max(v) * 1.18)),
        labels = fmt_n(pretty(c(0, max(v) * 1.18))), col = NA, col.ticks = PAL$grid)
      text(bp, v, labels = fmt_n(v), pos = 3, cex = 0.95, col = PAL$text)
    }
  })

  # -- Tables ------------------------------------------------------------------
  output$tbl_strata <- renderTable({
    s <- res()$strata
    data.frame(
      `Vaccination stratum` = s$stratum,
      `Share, baseline` = sprintf("%.1f%%", s$share_base),
      `Share, scenario` = sprintf("%.1f%%", s$share_scen),
      `Hospitalizations, baseline` = fmt_n(s$hosp_base),
      `Hospitalizations, scenario` = fmt_n(s$hosp_scen),
      `Excess hosp.` = fmt_n(s$hosp_excess),
      `ED visits, baseline` = fmt_n(s$ed_base),
      `ED visits, scenario` = fmt_n(s$ed_scen),
      `Excess ED` = fmt_n(s$ed_excess),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }, align = "lrrrrrrrr", width = "100%", spacing = "xs")

  output$tbl_summary <- renderTable({
    r <- res()
    data.frame(
      Quantity = c("AGE-related hospitalizations", "AGE-related ED visits",
        "Hospitalization expenditures", "ED expenditures", "Total expenditures",
        "Unit cost per hospitalization", "Unit cost per ED visit"),
      Baseline = c(fmt_n(r$baseline$hosp_total), fmt_n(r$baseline$ed_total),
        fmt_usd(r$baseline$cost_hosp), fmt_usd(r$baseline$cost_ed),
        fmt_usd(r$baseline$cost_total), fmt_usd(r$unit_cost_hosp), fmt_usd(r$unit_cost_ed)),
      Scenario = c(fmt_n(r$scenario$hosp_total), fmt_n(r$scenario$ed_total),
        fmt_usd(r$scenario$cost_hosp), fmt_usd(r$scenario$cost_ed),
        fmt_usd(r$scenario$cost_total), "", ""),
      Excess = c(fmt_n(r$excess$hosp), fmt_n(r$excess$ed),
        fmt_usd(r$excess$cost_hosp), fmt_usd(r$excess$cost_ed),
        fmt_usd(r$excess$cost_total), "", ""),
      `Relative excess` = c(sprintf("%+.1f%%", r$excess$pct_hosp),
        sprintf("%+.1f%%", r$excess$pct_ed), "", "",
        sprintf("%+.1f%%", r$excess$pct_cost), "", ""),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }, align = "lrrrr", width = "100%", spacing = "xs")

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
}

shinyApp(ui, server)
