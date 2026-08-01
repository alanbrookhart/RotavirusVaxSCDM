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

PARAMS   <- rv_param_table()
DEFAULTS <- rv_defaults()
GROUPS   <- unique(PARAMS$group)

PAL <- list(
  base   = "#94a3b8",
  excess = "#b91c1c",
  hosp   = "#1e40af",
  ed     = "#0e7490",
  grid   = "#e2e8f0",
  text   = "#1f2937"
)

# Build a slider for one parameter row, with the citation as a tooltip.
param_slider <- function(row) {
  tags$div(
    title = row$source,
    sliderInput(row$id, row$label,
      min = row$min, max = row$max, value = row$default,
      step = row$step, ticks = FALSE, width = "100%")
  )
}

param_panel <- function(group) {
  rows <- PARAMS[PARAMS$group == group, ]
  accordion_panel(
    group,
    lapply(seq_len(nrow(rows)), function(i) param_slider(rows[i, ]))
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
  "))),

  sidebar = sidebar(
    width = 380,
    open = "open",

    h6("Scenario", class = "text-uppercase text-muted mb-1"),
    sliderInput("shift", "Shift from fully vaccinated to unvaccinated (pct. points)",
      min = 0, max = 70, value = 10, step = 1, post = "%", ticks = FALSE),
    radioButtons("perspective", "Cost perspective",
      choices = c("Societal (direct + indirect)" = "societal",
                  "Direct medical only" = "direct"),
      selected = "societal"),
    numericInput("cohorts", "Number of annual birth cohorts", value = 1, min = 1, max = 20, step = 1),

    hr(),
    h6("Assumptions", class = "text-uppercase text-muted mb-1"),
    do.call(accordion, c(list(open = FALSE), lapply(GROUPS, param_panel))),
    checkboxInput("normalize", "Rescale uptake shares to sum to 100%", value = FALSE),
    actionButton("reset", "Reset to published values", class = "btn-outline-secondary btn-sm mt-2")
  ),

  # -- Projections -------------------------------------------------------------
  nav_panel(
    "Projections",
    layout_columns(
      col_widths = c(4, 4, 4),
      value_box("Excess hospitalizations", textOutput("vb_hosp"),
        showcase = NULL, theme = "primary"),
      value_box("Excess ED visits", textOutput("vb_ed"), theme = "secondary"),
      value_box("Excess expenditures", textOutput("vb_cost"), theme = "danger")
    ),
    uiOutput("warn"),
    layout_columns(
      col_widths = c(6, 6),
      card(
        card_header("Encounters per annual birth cohort, to age 2 years"),
        plotOutput("plot_counts", height = "330px")
      ),
      card(
        card_header("Excess burden by shift magnitude"),
        plotOutput("plot_shift", height = "330px")
      )
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

  # -- One-way sensitivity -----------------------------------------------------
  nav_panel(
    "One-way sensitivity",
    card(
      card_header("Vary a single parameter across its plausible range"),
      layout_columns(
        col_widths = c(6, 6),
        selectInput("ow_param", "Parameter",
          choices = stats::setNames(PARAMS$id, PARAMS$label),
          selected = "rh_unvax"),
        selectInput("ow_outcome", "Outcome", choices = rv_outcome_choices,
          selected = "excess_cost")
      ),
      plotOutput("plot_oneway", height = "400px"),
      div(class = "small text-muted px-2 pb-2", textOutput("ow_note"))
    )
  ),

  # -- Tornado -----------------------------------------------------------------
  nav_panel(
    "Tornado",
    card(
      card_header("Parameter influence at published confidence limits and plausible ranges"),
      selectInput("tor_outcome", "Outcome", choices = rv_outcome_choices,
        selected = "excess_cost", width = "320px"),
      plotOutput("plot_tornado", height = "620px")
    ),
    card(
      card_header("Tornado values"),
      tableOutput("tbl_tornado")
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

The scenario moves a specified share of the birth cohort from the fully
vaccinated to the unvaccinated stratum; the partially vaccinated strata are held
fixed, and the split of partially vaccinated children into one- and two-dose RV5
recipients is fixed at the person-time ratio observed in Butler et al. Table 1.

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
"At published values with a 10 percentage-point shift, the app reproduces the
accompanying spreadsheet: 20,202 baseline hospitalizations and 126,708 baseline
ED visits, and an excess of 1,485 hospitalizations and 4,383 ED visits.

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

  observeEvent(input$reset, {
    for (i in seq_len(nrow(PARAMS))) {
      updateSliderInput(session, PARAMS$id[i], value = PARAMS$default[i])
    }
    updateSliderInput(session, "shift", value = 10)
    updateRadioButtons(session, "perspective", selected = "societal")
    updateNumericInput(session, "cohorts", value = 1)
    updateCheckboxInput(session, "normalize", value = FALSE)
  })

  # Current parameter vector, falling back to defaults before sliders initialise.
  pars <- reactive({
    p <- DEFAULTS
    for (id in PARAMS$id) if (!is.null(input[[id]])) p[[id]] <- input[[id]]
    p
  })

  societal <- reactive(identical(input$perspective, "societal"))
  cohorts  <- reactive(max(1, as.numeric(input$cohorts %||% 1)))

  res <- reactive({
    rv_project(pars(), shift = input$shift, societal = societal(),
      cohorts = cohorts(), normalize = input$normalize)
  })

  # -- Value boxes -------------------------------------------------------------
  output$vb_hosp <- renderText(fmt_n(res()$excess$hosp))
  output$vb_ed   <- renderText(fmt_n(res()$excess$ed))
  output$vb_cost <- renderText(fmt_usd_short(res()$excess$cost_total))

  output$warn <- renderUI({
    r <- res()
    msgs <- character(0)
    if (!input$normalize && abs(r$share_sum - 100) > 0.05) {
      msgs <- c(msgs, sprintf(
        "Uptake shares sum to %.1f%%, not 100%%. The published values (13.9 / 15.3 / 70.7) sum to 99.9%% because of rounding; leaving this uncorrected reproduces the spreadsheet exactly.",
        r$share_sum))
    }
    if (r$shift_applied < input$shift - 1e-8) {
      msgs <- c(msgs, sprintf(
        "Requested shift of %g%% exceeds the fully vaccinated share; %.1f%% was applied.",
        input$shift, r$shift_applied))
    }
    if (!length(msgs)) return(NULL)
    div(class = "alert alert-warning py-2 small", lapply(msgs, tags$div))
  })

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

  # -- Excess by shift magnitude ----------------------------------------------
  output$plot_shift <- renderPlot({
    p <- pars()
    grid <- seq(0, 50, by = 2.5)
    if (max(grid) <= 0) return(invisible(NULL))
    vals <- vapply(grid, function(s) {
      rr <- rv_project(p, shift = s, societal = societal(), cohorts = cohorts(),
        normalize = input$normalize)
      c(rr$excess$hosp, rr$excess$ed, rr$excess$cost_total)
    }, numeric(3))

    op <- par(mar = c(4.5, 5.5, 2, 5.5), las = 1, bty = "n",
              col.axis = PAL$text, col.lab = PAL$text)
    on.exit(par(op))
    plot(grid, vals[2, ], type = "n", xlab = "Shift from fully vaccinated to unvaccinated (%)",
      ylab = "", yaxt = "n", ylim = c(0, max(vals[2, ]) * 1.05))
    abline(h = pretty(c(0, max(vals[2, ]))), col = PAL$grid)
    axis(2, at = pretty(c(0, max(vals[2, ]))), labels = fmt_n(pretty(c(0, max(vals[2, ])))),
      col = NA, col.ticks = PAL$grid)
    mtext("Excess encounters", side = 2, line = 4, las = 0, col = PAL$text)
    lines(grid, vals[2, ], col = PAL$ed, lwd = 3)
    lines(grid, vals[1, ], col = PAL$hosp, lwd = 3)

    # Cost is drawn on a secondary axis, rescaled to share the encounter panel.
    if (max(vals[3, ]) > 0 && max(vals[2, ]) > 0) {
      sc <- max(vals[2, ]) / max(vals[3, ])
      lines(grid, vals[3, ] * sc, col = PAL$excess, lwd = 3, lty = 3)
      at <- pretty(c(0, max(vals[3, ])))
      axis(4, at = at * sc, labels = fmt_usd_short(at), col = NA, col.ticks = PAL$grid)
      mtext("Excess expenditures", side = 4, line = 4, las = 0, col = PAL$text)
    }

    abline(v = input$shift, col = "#64748b", lty = 2)
    legend("topleft", bty = "n", lwd = 3, lty = c(1, 1, 3),
      col = c(PAL$ed, PAL$hosp, PAL$excess),
      legend = c("ED visits", "Hospitalizations", "Expenditures"), cex = 0.9)
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
        sprintf("%+.1f%%", r$excess$pct_ed), "", "", "", "", ""),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }, align = "lrrrr", width = "100%", spacing = "xs")

  output$tbl_sources <- renderTable({
    num <- function(x) formatC(x, format = "fg", digits = 7, big.mark = ",")
    data.frame(
      Parameter = PARAMS$label,
      `Published value` = num(PARAMS$default),
      Low = num(PARAMS$low),
      High = num(PARAMS$high),
      Source = PARAMS$source,
      check.names = FALSE, stringsAsFactors = FALSE)
  }, align = "lrrrl", width = "100%", spacing = "xs")

  # -- One-way -----------------------------------------------------------------
  output$plot_oneway <- renderPlot({
    d <- rv_oneway(pars(), input$ow_param, outcome = input$ow_outcome,
      shift = input$shift, societal = societal(), cohorts = cohorts(),
      normalize = input$normalize)
    row <- PARAMS[PARAMS$id == input$ow_param, ]
    is_cost <- grepl("cost", input$ow_outcome)
    lab <- names(rv_outcome_choices)[match(input$ow_outcome, rv_outcome_choices)]

    op <- par(mar = c(4.5, 6.5, 2, 1), las = 1, bty = "n",
              col.axis = PAL$text, col.lab = PAL$text)
    on.exit(par(op))
    yl <- range(c(0, d$outcome))
    if (diff(yl) <= 0) yl <- c(-1, 1)
    plot(d$value, d$outcome, type = "n", xlab = row$label, ylab = "",
      yaxt = "n", ylim = yl)
    abline(h = pretty(yl), col = PAL$grid)
    at <- pretty(yl)
    axis(2, at = at, labels = if (is_cost) fmt_usd_short(at) else fmt_n(at),
      col = NA, col.ticks = PAL$grid)
    mtext(lab, side = 2, line = 5, las = 0, col = PAL$text)
    lines(d$value, d$outcome, col = PAL$hosp, lwd = 3)

    y0 <- rv_outcome(rv_project(pars(), input$shift, societal(), cohorts(), input$normalize),
      input$ow_outcome)
    points(row$default, y0, pch = 21, bg = PAL$excess, col = "white", cex = 2, lwd = 2)
    text(row$default, y0, "published value", pos = 4, cex = 0.85, col = PAL$excess)
  })

  output$ow_note <- renderText({
    row <- PARAMS[PARAMS$id == input$ow_param, ]
    sprintf("Range %s to %s. %s", format(row$low), format(row$high), row$source)
  })

  # -- Tornado -----------------------------------------------------------------
  tor <- reactive({
    rv_tornado(pars(), outcome = input$tor_outcome, shift = input$shift,
      societal = societal(), cohorts = cohorts(), normalize = input$normalize)
  })

  output$plot_tornado <- renderPlot({
    td <- tor()
    is_cost <- grepl("cost", input$tor_outcome)
    lab <- names(rv_outcome_choices)[match(input$tor_outcome, rv_outcome_choices)]
    base <- td$base[1]
    n <- nrow(td)

    op <- par(mar = c(4.5, 20, 3, 2), las = 1, bty = "n",
              col.axis = PAL$text, col.lab = PAL$text)
    on.exit(par(op))

    xl <- range(c(td$lower, td$upper, base))
    # A zero shift makes every excess outcome identically zero, collapsing the
    # axis; widen it so the plot still renders and the message is legible.
    if (diff(xl) <= 0) xl <- xl + c(-1, 1) * max(1, abs(base) * 0.05)
    xl <- xl + c(-0.06, 0.06) * diff(xl)

    plot(NA, xlim = xl, ylim = c(0.4, n + 0.6), xlab = lab, ylab = "",
      yaxt = "n", xaxt = "n")
    at <- pretty(xl)
    axis(1, at = at, labels = if (is_cost) fmt_usd_short(at) else fmt_n(at),
      col = NA, col.ticks = PAL$grid)
    abline(v = at, col = PAL$grid)
    rect(pmin(td$lower, base), seq_len(n) - 0.32, base, seq_len(n) + 0.32,
      col = PAL$base, border = NA)
    rect(base, seq_len(n) - 0.32, pmax(td$upper, base), seq_len(n) + 0.32,
      col = PAL$excess, border = NA)
    abline(v = base, col = PAL$text, lwd = 2)
    axis(2, at = seq_len(n), labels = td$label, tick = FALSE,
      cex.axis = 0.88, col.axis = PAL$text)
    mtext(sprintf("Base case: %s   |   shift = %g%%   |   grey = parameter at lower bound, red = upper bound",
      if (is_cost) fmt_usd(base) else fmt_n(base), input$shift),
      side = 3, line = 0.5, adj = 0, cex = 0.85, col = PAL$text)
  })

  output$tbl_tornado <- renderTable({
    td <- tor()
    td <- td[rev(seq_len(nrow(td))), ]
    is_cost <- grepl("cost", input$tor_outcome)
    f <- if (is_cost) fmt_usd else function(x) fmt_n(x)
    pct <- ifelse(td$base == 0, "—",
      sprintf("%.1f%%", 100 * td$swing / td$base))
    data.frame(
      Parameter = td$label,
      `Low input` = format(td$low_value),
      `High input` = format(td$high_value),
      `Outcome at low` = f(td$at_low),
      `Outcome at high` = f(td$at_high),
      Swing = f(td$swing),
      `Swing, % of base` = pct,
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }, align = "lrrrrrr", width = "100%", spacing = "xs")
}

shinyApp(ui, server)
