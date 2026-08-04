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

GROUPS    <- rv_groups()
SCALARS   <- rv_scalars()
SCEN      <- rv_scenarios()
RD_BOUNDS <- rv_rd_bounds()

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

# One editable cell. The grid's header row supplies the visible labelling, so
# each numericInput carries no label of its own -- but a suppressed label leaves
# the input with no accessible name, and a screen reader cannot infer one from
# the column header. `aria` supplies it. htmltools ships with shiny, so this
# adds no package to the Shinylive bundle.
grid_cell <- function(id, value, step, aria) {
  ni <- numericInput(id, label = NULL, value = value, step = step,
    width = "100%")
  ni <- htmltools::tagQuery(ni)$find("input")$addAttrs("aria-label" = aria)$allTags()
  tags$td(ni)
}

# The partially vaccinated risks are not typed. They are the share-weighted
# average of the one- and two-dose RV5 levels, set by the weight in the sidebar,
# so they are rendered read-only. Keeping them derived rather than editable also
# means the displayed rounding costs nothing: the model uses the exact blend
# while the cell shows four decimals.
derived_cell <- function(output_id) {
  tags$td(class = "derived-cell", textOutput(output_id, inline = TRUE))
}

group_grid <- function() {
  rows <- lapply(seq_len(nrow(GROUPS)), function(i) {
    g <- GROUPS[i, ]
    derived <- identical(g$id, "partial")
    tags$tr(
      tags$th(g$label, scope = "row", class = "grid-label"),
      grid_cell(paste0("cur_",  g$id), g$share,         0.1,
        paste(g$label, "current percent")),
      grid_cell(paste0("scen_", g$id), SCEN_DEFAULT[i], 0.1,
        paste(g$label, "scenario percent")),
      if (derived) derived_cell("blend_h") else
        grid_cell(paste0("rh_", g$id), g$risk_h, 0.01,
          paste(g$label, "hospitalization risk percent")),
      if (derived) derived_cell("blend_e") else
        grid_cell(paste0("re_", g$id), g$risk_e, 0.01,
          paste(g$label, "ED visit risk percent"))
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

scalar_input <- function(row) {
  tags$div(
    title = row$source,
    if (identical(row$widget, "slider")) {
      sliderInput(row$id, row$label, min = row$min, max = row$max,
        value = row$default, step = row$step, ticks = FALSE, width = "100%")
    } else {
      numericInput(row$id, row$label, value = row$default, min = row$min,
        max = row$max, step = row$step, width = "100%")
    }
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
    .derived-cell { color: #475569; font-style: italic; padding-left: .85rem; }
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
    lapply(seq_len(nrow(SCALARS)), function(i) scalar_input(SCALARS[i, ])),

    hr(),
    h6("Composition of the partially vaccinated",
      class = "text-uppercase text-muted mb-1"),
    div(
      title = paste("Sederdahl et al. report only a single lumped 15.3%",
                    "partially vaccinated. This weight apportions it between",
                    "the one- and two-dose RV5 levels, whose two-year risks",
                    "Butler et al. report separately. Default is the",
                    "person-time ratio in Butler Table 1,",
                    "162196/(162196+323558)."),
      numericInput("w_partial1", "One dose, % of partially vaccinated",
        value = round(rv_partial_components()$w_default, 6),
        min = 0, max = 100, step = 0.1, width = "100%")
    ),
    div(class = "small text-muted mb-2",
      "Sets the blended risks in the grid. Has no effect on the projected",
      "excess, since the partially vaccinated are held fixed across scenarios;",
      "it moves the baseline only."),

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
        div(class = "d-flex gap-2 align-items-center mt-2 flex-wrap",
          span(class = "small text-muted me-1", "Hypothetical Effect of SDM:"),
          actionButton("fill_10", "10%", class = "btn-outline-primary btn-sm"),
          actionButton("fill_20", "20%", class = "btn-outline-primary btn-sm"),
          actionButton("fill_30", "30%", class = "btn-outline-primary btn-sm")
        ),
        div(class = "d-flex gap-2 align-items-center mt-2 flex-wrap",
          span(class = "small text-muted me-1", "Vaccine effect at 95% CI bounds:"),
          actionButton("rd_lower", "Stronger", class = "btn-outline-secondary btn-sm",
            title = paste("Set the full-series risk difference to the lower confidence",
                          "limit: -0.50 for hospitalization, -1.43 for ED visits.",
                          "A larger protective effect, so a larger projected excess.")),
          actionButton("rd_upper", "Weaker", class = "btn-outline-secondary btn-sm",
            title = paste("Set the full-series risk difference to the upper confidence",
                          "limit: -0.31 for hospitalization, -1.00 for ED visits.",
                          "A smaller protective effect, so a smaller projected excess.")),
          span(class = "small text-muted ms-1",
            "Butler et al. 2021, Table 1 and Table 2 risk differences")
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
vaccinated stratum fixed.

Butler et al. estimate separate risks for children who received one dose and two
doses of the three-dose RV5 series. The partially vaccinated row shown here
carries the share-weighted average of the two, using the proportion set under
*Composition of the partially vaccinated* in the sidebar. Its two risk cells are
therefore displayed rather than edited.

The Stronger and Weaker buttons set the full-series risks so that the risk
difference against unvaccinated equals the lower or upper 95% confidence limit
reported by Butler et al. Because the scenario moves children between these two
strata alone, the projected excess is proportional to that risk difference, so
these bounds carry directly through to the projection. Note that they also change
the baseline, since most of the cohort is fully vaccinated, and that setting the
hospitalization and ED limits together assumes both err in the same direction --
they bracket the projection rather than forming a 95% interval around it.

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

Costs are reported from a societal perspective by default, combining direct
medical costs with indirect costs. The cost perspective control in the sidebar
switches to direct medical costs alone."
        )
      )
    )
  ),

  nav_spacer(),
  nav_item(tags$a("Source", href = "https://github.com/", target = "_blank"))
)


# --- Server -------------------------------------------------------------------

server <- function(input, output, session) {

  # Percent of the partially vaccinated who received one dose. Drives the
  # blended risks for that stratum; nothing else reads it.
  w_partial1 <- reactive({
    rv_num(input$w_partial1, rv_partial_components()$w_default)
  })

  gvals <- reactive({
    g <- GROUPS
    g$share  <- vapply(GROUPS$id, function(i)
      rv_num(input[[paste0("cur_", i)]], GROUPS$share[GROUPS$id == i]), numeric(1))
    g$risk_h <- vapply(GROUPS$id, function(i)
      rv_num(input[[paste0("rh_", i)]], GROUPS$risk_h[GROUPS$id == i]), numeric(1))
    g$risk_e <- vapply(GROUPS$id, function(i)
      rv_num(input[[paste0("re_", i)]], GROUPS$risk_e[GROUPS$id == i]), numeric(1))

    # The partially vaccinated row has no input cells -- its risks are derived
    # from the weight, at full precision. `rv_num` above fell back to the
    # registry defaults for it; overwrite with the live blend.
    b <- rv_blend_partial(w_partial1())
    k <- which(GROUPS$id == "partial")
    g$risk_h[k] <- b[["hosp"]]
    g$risk_e[k] <- b[["ed"]]
    g
  })

  output$blend_h <- renderText(sprintf("%.4f", rv_blend_partial(w_partial1())[["hosp"]]))
  output$blend_e <- renderText(sprintf("%.4f", rv_blend_partial(w_partial1())[["ed"]]))

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

  # Risk-difference sensitivity. Sets the full-series risks so the difference
  # from unvaccinated equals a confidence limit, reading the unvaccinated risks
  # from the grid rather than a constant so the buttons respect an edited
  # reference. `local()` is load-bearing here for the same reason as above.
  for (bd in c("lower", "upper")) local({
    bound <- bd
    observeEvent(input[[paste0("rd_", bound)]], {
      g <- rv_apply_rd(gvals(), RD_BOUNDS[[bound]])
      n <- nrow(g)
      updateNumericInput(session, paste0("rh_", GROUPS$id[n]),
        value = round(g$risk_h[n], 6))
      updateNumericInput(session, paste0("re_", GROUPS$id[n]),
        value = round(g$risk_e[n], 6))
    }, ignoreInit = TRUE)
  })

  observeEvent(input$reset, {
    for (k in seq_len(nrow(GROUPS))) {
      updateNumericInput(session, paste0("cur_",  GROUPS$id[k]), value = GROUPS$share[k])
      updateNumericInput(session, paste0("scen_", GROUPS$id[k]), value = SCEN_DEFAULT[k])
      # The partially vaccinated risks are derived, not inputs; restoring the
      # weight below puts them back.
      if (!identical(GROUPS$id[k], "partial")) {
        updateNumericInput(session, paste0("rh_", GROUPS$id[k]), value = GROUPS$risk_h[k])
        updateNumericInput(session, paste0("re_", GROUPS$id[k]), value = GROUPS$risk_e[k])
      }
    }
    updateNumericInput(session, "w_partial1",
      value = round(rv_partial_components()$w_default, 6))
    for (i in seq_len(nrow(SCALARS))) {
      if (identical(SCALARS$widget[i], "slider")) {
        updateSliderInput(session, SCALARS$id[i], value = SCALARS$default[i])
      } else {
        updateNumericInput(session, SCALARS$id[i], value = SCALARS$default[i])
      }
    }
    updateRadioButtons(session, "perspective", selected = "societal")
    updateNumericInput(session, "cohorts", value = 1)
  })

  # A plain column total, always muted. Deliberately carries no commentary about
  # whether it reaches 100%: the published shares sum to 99.9% because of
  # rounding in the source, and flagging that is a note for the authors, not
  # something to put in front of a reader.
  sum_badge <- function(total) {
    span(class = "grid-sum", sprintf("%.1f%%", total))
  }

  output$sum_cur  <- renderUI(sum_badge(sum(gvals()$share)))
  output$sum_scen <- renderUI(sum_badge(sum(scen_share())))

  # Input id -> human label, for naming blanks in the banner. Covers the sidebar
  # scalars as well as the grid: `rv_num()` reads a cleared box as 0, so a blank
  # cost silently zeroes a whole expenditure column and must be reported too.
  CELL_LABELS <- local({
    prefixes <- c(cur = "current %", scen = "scenario %",
                  rh = "hospitalization risk", re = "ED risk")
    ids <- character(0); labs <- character(0)
    for (p in names(prefixes)) {
      for (k in seq_len(nrow(GROUPS))) {
        # The partially vaccinated risk cells are derived, so there is no input
        # to be left blank.
        if (p %in% c("rh", "re") && identical(GROUPS$id[k], "partial")) next
        ids  <- c(ids,  paste0(p, "_", GROUPS$id[k]))
        labs <- c(labs, paste0(GROUPS$label[k], " — ", prefixes[[p]]))
      }
    }
    stats::setNames(c(labs, SCALARS$label, "One dose, % of partially vaccinated"),
                    c(ids, SCALARS$id, "w_partial1"))
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
    # Two decimals, and no trailing ".00" on whole numbers like the birth count.
    num <- function(x) {
      s <- formatC(x, format = "f", digits = 2, big.mark = ",")
      sub("\\.00$", "", s)
    }
    g <- GROUPS
    # Row counts follow nrow(g) rather than a literal: the number of strata has
    # changed once already, and a hardcoded count fails only at render time.
    n <- nrow(g)
    src <- function(base, blended) ifelse(g$id == "partial", blended, base)

    rbind(
      data.frame(
        Parameter = c(paste("Share,", g$label),
                      paste("Hospitalization risk,", g$label),
                      paste("ED visit risk,", g$label)),
        `Published value` = num(c(g$share, g$risk_h, g$risk_e)),
        Source = c(
          rep("Sederdahl et al. Pediatrics 2019", n),
          src("Butler et al. 2021, Table 1",
              "Weighted average of the one- and two-dose RV5 levels, Butler et al. 2021 Table 1"),
          src("Butler et al. 2021, Table 2",
              "Weighted average of the one- and two-dose RV5 levels, Butler et al. 2021 Table 2")),
        check.names = FALSE, stringsAsFactors = FALSE),
      data.frame(
        Parameter = "One dose, % of partially vaccinated",
        `Published value` = num(rv_partial_components()$w_default),
        Source = "Person-time ratio in Butler et al. 2021 Table 1, 162196/(162196+323558)",
        check.names = FALSE, stringsAsFactors = FALSE),
      data.frame(
        Parameter = c("Risk difference, hospitalization", "Risk difference, ED visit"),
        `Published value` = c("-0.40 (-0.50, -0.31)", "-1.22 (-1.43, -1.00)"),
        Source = rep(paste("Butler et al. 2021, Table 1 and Table 2;",
                           "sets the Stronger and Weaker buttons"), 2),
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
