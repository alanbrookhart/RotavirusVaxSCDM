# Rotavirus SCDM Sensitivity Analysis

An interactive sensitivity analysis accompanying Butler AM, Panozzo CA, Boutzoukas AE, Brookhart MA, *"Rotavirus Vaccination: Impact of New Recommendation"* (research letter, under revision).

The application lets a reader vary every parameter and assumption underlying the published projection — annual births, the vaccination uptake distribution under both the current and a comparison scenario, the two-year risks of AGE-related hospitalization and emergency department visits, and the per-episode unit costs — and see immediately how the projected excess burden and expenditures respond.

It is a Shiny application exported with [Shinylive](https://posit-dev.github.io/r-shinylive/), so R runs in the browser under WebAssembly. The published site is entirely static and requires no Shiny server.

## Repository layout

```
app/
  app.R              Shiny UI and server
  model.R            The projection model and parameter registry (no Shiny code)
tests/
  test-model.R       Regression tests against the source spreadsheet
build.R              Exports app/ to a static Shinylive site in _site/
.github/workflows/
  deploy.yml         Builds and publishes to GitHub Pages on push to main
docs/                Manuscript, response to reviewers, and source spreadsheet
```

`model.R` is deliberately free of Shiny dependencies. It can be sourced on its own for scripted analyses, and it is what the tests exercise.

## Running locally

```r
# once
install.packages(c("shiny", "bslib", "shinylive"))

# run the app directly
shiny::runApp("app")

# run the regression tests
source("tests/test-model.R")

# build the static site and preview it
source("build.R")
httpuv::runStaticServer("_site")
```

## Publishing to GitHub Pages

The included workflow does the build in CI and publishes through the Pages deployment action, so no build output is committed to the repository. After creating the remote:

```bash
git init
git add .
git commit -m "Rotavirus SCDM sensitivity analysis"
git branch -M main
git remote add origin git@github.com:<user>/<repo>.git
git push -u origin main
```

Then in the repository settings, under **Pages**, set **Source** to **GitHub Actions**. The first push to `main` will build and deploy; subsequent pushes that touch `app/`, `tests/`, or `build.R` will redeploy.

Note that the site is published from a CI artifact rather than from the `docs/` folder, because `docs/` in this repository holds the manuscript and the source spreadsheet. If you would rather serve from `docs/`, move those files first — otherwise they become publicly downloadable.

The exported Shinylive site is on the order of 30–40 MB, since it bundles the webR runtime and the required R packages. This is well within GitHub Pages limits but is the reason the build is not committed.

## The model

For each vaccination stratum *s*:

```
encounters_s = births × share_s × two_year_risk_s
cost         = Σ hospitalizations × unit_cost_hospitalization
             + Σ ED visits        × unit_cost_ED
```

Two-year cumulative incidences come from Butler et al. (*Epidemiology* 2021;32:598–606), estimated with inverse probability of censoring weighting in a commercially insured birth cohort.

### Entering a scenario

The Current and Scenario columns of the group grid are typed directly, so any pair of uptake distributions can be compared — including scenarios the published letter cannot express, such as children moving into partial vaccination rather than out of it altogether.

The **10%**, **20%** and **30%** buttons fill the Scenario column with the published scenarios, which move that many percentage points from the fully vaccinated stratum into the unvaccinated one while holding the partially vaccinated strata fixed. Because only two strata move and the risks are constants, the excess is exactly linear in the shift magnitude.

The published shares (13.9% unvaccinated, 15.3% partially vaccinated, 70.7% fully vaccinated) sum to 99.9% because of rounding. The app reports each column's sum but does not correct it: auto-normalising would leave the app unable to reproduce the letter.

### The partially vaccinated stratum

Butler et al. report the partially vaccinated as **two** strata — one dose and two doses of the three-dose RV5 series — with distinct two-year risks (0.80% and 0.61% for hospitalization, 4.57% and 4.23% for ED visits). The uptake source, Sederdahl et al., reports only a single lumped 15.3%. Apportioning that 15.3% between the two levels therefore requires an assumption that appears nowhere in the letter.

The app carries **one** partially vaccinated stratum whose risks are the share-weighted average of the two levels, with the weight exposed as a single sidebar parameter, *One dose, % of partially vaccinated*. The two risk cells for that row are shown read-only in the grid because they are derived rather than entered.

**This is not an approximation.** The model is linear in the stratum shares, so a blended stratum reproduces the two-stratum result exactly, for any weight. `tests/test-model.R` asserts the identity at weights of 0, 20, 33.39, 50 and 100% against an explicit four-row build, agreeing to within 1e-6 on both baseline and excess.

Two consequences worth understanding:

- **The weight cannot affect the projected excess at all.** Both partial levels are held fixed between the current and scenario columns, so their contribution cancels in the difference. The test asserts this: across weights from 0 to 100% the excess is invariant to nine decimals. What the weight moves is the *baseline* — from $542.6M at a weight of 0 to $565.6M at 100%, against $550.2M at the default.
- **Collapsing improved fidelity.** The four-stratum version had to carry the split as two share literals rounded to six decimals (5.108756% and 10.191244%), which left the baseline counts 2e-5 off the spreadsheet. Deriving the blend from the weight is exact, and baseline hospitalizations and ED visits now match cells `K19` and `K60` to within 2e-7.

The default weight is the person-time ratio in Butler et al. Table 1, `162196/(162196+323558)` = 33.3906%, which is what the source spreadsheet assumes. Note that person-time is not the same quantity as the share of children: a child who remains permanently at one dose contributes one-dose person-time across the whole of follow-up, whereas a child who completes the series contributes only the interdose interval. The weight is exposed precisely so that this assumption can be varied rather than buried.

Confidence limits are deliberately **not** carried for this row. Its risk is a mixture of two estimates, and averaging two confidence limits does not produce a confidence limit for the mixture.

### Risk-difference sensitivity

The **Stronger** and **Weaker** buttons set the full-series risks so that the risk difference against unvaccinated equals a 95% confidence limit from Butler et al. — Table 1 cell `E18`, −0.40 (−0.50, −0.31) for hospitalization, and Table 2 cell `E59`, −1.22 (−1.43, −1.00) for ED visits. Both risks move together, and the unvaccinated risk is read from the grid rather than a constant, so an edited reference is honoured.

That contrast is the one Butler et al. actually estimated and bootstrapped, and because the scenario moves people strictly between the full-series and unvaccinated strata, the projected excess is exactly linear in it. A bound on the risk difference therefore maps directly onto a bound on the excess, with no further assumption. At the 30% scenario this gives roughly $79M to $126M around a $103.5M point estimate.

Two caveats. Because the buttons change the full-series risk, they also move the baseline — 70.7% of the cohort sits in that stratum — so the relative-excess percentages shift as well; the interval is not a pure perturbation of the excess. And taking the hospitalization and ED limits together assumes the two err in the same direction, which overstates the width of a joint interval. Present it as a pre-specified bounding analysis rather than a 95% confidence interval.

The source rounds inconsistently here: differencing the rounded risks gives −0.41 and −1.21, where the paper's risk-difference column reports −0.40 and −1.22. The app anchors on the unvaccinated risk, which is the reading that matches setting the risk difference to its limit.

## Verification

`tests/test-model.R` checks the R implementation against specific cells of `docs/RV spreadsheet.xlsx`. The encounter counts reproduce to within 2e-7. The expenditure figures sit $17 to $420 below the spreadsheet, for the one deliberate reason given below.

| Quantity | Model | Spreadsheet |
| --- | --- | --- |
| Baseline hospitalizations (K19) | 20,201.714152 | 20,201.714152 |
| Baseline ED visits (K60) | 126,708.413902 | 126,708.413902 |
| Baseline expenditures (W23) | $550,236,525.40 | $550,236,945.15 |
| Excess expenditures, 10% shift (X24) | $34,508,414.69 | $34,508,431.45 |
| Excess expenditures, 20% shift (X25) | $69,016,829.37 | $69,016,862.91 |
| Excess expenditures, 30% shift (X26) | $103,525,244.06 | $103,525,294.36 |

### Why the expenditure figures differ

The indirect cost per episode is a **cost**, so this model rounds it to whole cents: $423.78. The spreadsheet does not. Its cell `Indirect costs!N45` is `=(H45+P24)`, where `H45` is two days of $1,117 weekly earnings taken over a seven-day week — and since seven does not divide 1,117, Excel carries the repeating decimal $423.782857142857… into every dollar cell downstream.

Nothing the letter reports moves. Both printed figures are unchanged at $34.5M and $103.5M, footnote d's percentages are identical to four decimals (6.2716% and 18.8147%), and the encounter counts do not involve cost at all.

The equivalence is proved rather than asserted. `tests/test-model.R` has a *Spreadsheet equivalence* block that restores the unrounded intermediate and checks that `W23` and `X24`–`X26` come back to within $1 — so the rounding is demonstrably the only difference. If that block ever fails, the model and the spreadsheet have genuinely diverged.

Rounding `N45` to two decimals in the spreadsheet would remove the discrepancy at source, and would change the published 30% figure from $103,525,294 to $103,525,244 — still $103.5M.


## Parameter sources

| Parameter | Value | Source |
| --- | --- | --- |
| Annual U.S. births | 3,622,673 | CDC Vital Statistics Rapid Release No. 38 (provisional 2024) |
| Uptake distribution | 13.9 / 15.3 / 70.7 % | Sederdahl et al. *Pediatrics* 2019 |
| One dose, % of partially vaccinated | 33.390564 | Person-time ratio in Butler et al. 2021 Table 1, 162196/(162196+323558) |
| Two-year hospitalization risks | 0.88 / 0.673442 / 0.47 % | Butler et al. *Epidemiology* 2021, Table 1; middle value is the weighted blend of 0.80 and 0.61 |
| Two-year ED visit risks | 4.36 / 4.343528 / 3.15 % | Butler et al. *Epidemiology* 2021, Table 2; middle value is the weighted blend of 4.57 and 4.23 |
| Risk difference, full series vs unvaccinated | −0.40 (−0.50, −0.31) hosp; −1.22 (−1.43, −1.00) ED | Butler et al. 2021, Table 1 `E18` and Table 2 `E59`; drives the Stronger/Weaker buttons |
| Cost per hospitalization (direct) | \$19,251.56 | Karve et al. 2014, CPI-inflated to January 2025 |
| Cost per ED visit (direct) | \$781.83 | Karve et al. 2014, CPI-inflated to January 2025 |
| Indirect cost per episode | \$423.78 | Two days of median weekly earnings (BLS CPS 2023, $1,117/wk over a 7-day week) plus $104.64 median out-of-pocket costs, rounded to cents |

The published 95% confidence limits on the individual risks are retained in `rv_groups()` and `rv_scalars()` as `_lo`/`_hi` columns. Nothing consumes them: the sensitivity analysis uses `rv_rd_bounds()` on the full-series contrast instead, for the reasons given above. The partially vaccinated row carries `NA` bounds deliberately.

Two notes on the indirect cost that belong in any methods write-up. The $104.64 of out-of-pocket items is from Widdowson et al., CPI-inflated, but Widdowson's own forgone-earnings figure ($118/day in 2004, $202.40 inflated to 2025) is *excluded* and replaced by the BLS calculation — reasonable, since 2023 BLS data are fresher and using both would double-count, but not what the citation implies. And dividing median weekly earnings by seven yields a notional $159.57/day that no one actually forgoes; BLS reports earnings for full-time workers over a five-day week, so a lost workday is nearer $223.40. The five-day denominator would raise the indirect cost to $551.44 and the 30% estimate to about $105.8M. The current choice errs downward, consistent with the letter's framing of these as minimum estimates.

Annual births remains a `sliderInput`; the three cost parameters (`c_hosp`, `c_ed`, `c_indirect`) are `numericInput`s. This is not cosmetic: `updateSliderInput()` round-trips a value through ionRangeSlider, which rounds it to the decimal count implied by `step`, and with `step >= 1` that is zero decimals — a reset once turned `c_indirect`'s then-unrounded `423.782857142857` into `424` and the app stopped reproducing the source spreadsheet. Typed numeric inputs do not coerce to a step grid, so exact values survive both initial load and reset. This still matters now that the cost is rounded to cents: `c_hosp` at `19251.56` and `c_ed` at `781.83` would both be flattened to whole dollars by a slider.

## Possible extensions

- **Probabilistic sensitivity analysis.** Draw the full-series risk difference from its reported limits and the costs from lognormal distributions, and report medians with intervals. The deterministic bounding version is already implemented (see *Risk-difference sensitivity* above). Note that the bootstrap confidence intervals in Butler et al. are marginal, so treating hospitalization and ED effects as independent understates their correlation while taking both at their limits overstates it.
- **Indirect (herd) protection.** A multiplier on risk in the unvaccinated stratum, addressing the first stated limitation. Whether this widens or narrows the excess depends on whether the multiplier is held fixed or allowed to scale with coverage, which is the substantively interesting question.
- **Outpatient visits.** Excluded because Butler et al. report no risk estimates for AGE-related outpatient care, which is the binding constraint rather than the arithmetic.
