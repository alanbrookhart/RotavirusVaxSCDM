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

The partially vaccinated 15.3% is split into one- and two-dose RV5 recipients at the person-time ratio in Butler et al. Table 1, shown to six decimals as 5.108756% and 10.191244%. That rounding lands within $0.43 of the spreadsheet's baseline expenditure; carrying fewer digits would cost materially more.

## Verification

`tests/test-model.R` checks the R implementation against specific cells of `docs/RV spreadsheet.xlsx`. The encounter counts reproduce to within 0.01 encounters. The expenditure figures sit $17 to $420 below the spreadsheet, for one deliberate reason given below.

| Quantity | Model | Spreadsheet |
| --- | --- | --- |
| Baseline hospitalizations (K19) | 20,201.71 | 20,201.71 |
| Baseline ED visits (K60) | 126,708.41 | 126,708.41 |
| Baseline expenditures (W23) | $550,236,524.98 | $550,236,945.15 |
| Excess expenditures, 10% shift (X24) | $34,508,414.69 | $34,508,431.45 |
| Excess expenditures, 20% shift (X25) | $69,016,829.37 | $69,016,862.91 |
| Excess expenditures, 30% shift (X26) | $103,525,244.06 | $103,525,294.36 |

### Why the expenditure figures differ

The indirect cost per episode is a **cost**, so this model rounds it to whole cents: $423.78. The spreadsheet does not. Its cell `Indirect costs!N45` is `=(H45+P24)`, where `H45` is two days of $1,117 weekly earnings taken over a seven-day week — and since seven does not divide 1,117, Excel carries the repeating decimal $423.782857142857… straight into every dollar cell downstream.

Nothing the letter reports moves. Both printed figures are unchanged at $34.5M and $103.5M, footnote d's percentages are identical to four decimals (6.2716% and 18.8147%), and the encounter counts do not involve cost at all.

The equivalence is still proved rather than asserted. `tests/test-model.R` has a "Spreadsheet equivalence" block that restores the unrounded intermediate and checks that `W23` and `X24`–`X26` come back to within $1 — so the rounding is demonstrably the *only* difference between the two. If that block ever fails, the model and the spreadsheet have genuinely diverged.

Rounding `N45` to two decimals in the spreadsheet would remove the discrepancy at source, and would change the published 30% figure from $103,525,294 to $103,525,244 — still $103.5M.

### One discrepancy worth resolving before resubmission

The letter reports **\$32.0 million** for a 10% shift and **\$103.5 million** for a 30% shift. These are not on the same footing:

- \$32.0 million is the excess under a **direct medical** perspective (the model gives \$32,021,364).
- \$103.5 million is the excess under a **societal** perspective (direct plus indirect costs).

The corresponding matched figures are \$34.5 million (10% shift, societal) and \$96.1 million (30% shift, direct medical). Since the Methods section states that costs were defined from a societal perspective, the 10% figure appears to be the one that needs updating, to \$34.5 million. The app's cost-perspective control reproduces either convention.

## Parameter sources

| Parameter | Value | Source |
| --- | --- | --- |
| Annual U.S. births | 3,622,673 | CDC Vital Statistics Rapid Release No. 38 (provisional 2024) |
| Uptake distribution | 13.9 / 5.108756 / 10.191244 / 70.7 % | Sederdahl et al. *Pediatrics* 2019; partial split from Butler et al. 2021 Table 1 |
| Two-year hospitalization risks | 0.88 / 0.80 / 0.61 / 0.47 % | Butler et al. *Epidemiology* 2021, Table 1 |
| Two-year ED visit risks | 4.36 / 4.57 / 4.23 / 3.15 % | Butler et al. *Epidemiology* 2021, Table 2 |
| Cost per hospitalization (direct) | \$19,251.56 | Karve et al. 2014, CPI-inflated to January 2025 |
| Cost per ED visit (direct) | \$781.83 | Karve et al. 2014, CPI-inflated to January 2025 |
| Indirect cost per episode | \$423.78 | Two days of median weekly earnings (BLS CPS 2023, $1,117/wk over a 7-day week) plus $104.64 median out-of-pocket costs, rounded to cents |

The published 95% confidence limits are retained in `rv_groups()` and `rv_scalars()` as `_lo`/`_hi` columns. Nothing consumes them yet; they are the input for the sensitivity analysis planned as follow-up work.

Annual births remains a `sliderInput`; the three cost parameters (`c_hosp`, `c_ed`, `c_indirect`) are `numericInput`s. This is not cosmetic: `updateSliderInput()` round-trips a value through ionRangeSlider, which rounds it to the decimal count implied by `step`, and with `step >= 1` that is zero decimals — a reset once turned `c_indirect`'s then-unrounded `423.782857142857` into `424` and the app stopped reproducing the source spreadsheet. Typed numeric inputs do not coerce to a step grid, so exact values survive both initial load and reset. That still matters now that the cost is rounded to cents: `c_hosp` at `19251.56` and `c_ed` at `781.83` would both be flattened to whole dollars by a slider.

## Possible extensions

Two features were scoped out of this draft but are straightforward to add, since `rv_project()` already takes the relevant arguments or is easily generalized:

- **Sensitivity analysis.** The agreed next piece of work, and the answer to Reviewer #3's request that uncertainty be incorporated into the projections. The confidence limits it needs are already carried in `rv_groups()` and `rv_scalars()`. Note that the bootstrap confidence intervals in Butler et al. are marginal, so treating the four stratum-specific risks as independent will overstate the width of any resulting interval.
- **Indirect (herd) protection.** A multiplier on risk in the unvaccinated stratum, addressing the first stated limitation. Whether this widens or narrows the excess depends on whether the multiplier is held fixed or allowed to scale with coverage, which is the substantively interesting question.
