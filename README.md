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

The Pre-SCDM and Scenario columns of the group grid are typed directly, so any pair of uptake distributions can be compared — including scenarios the published letter cannot express, such as children moving into partial vaccination rather than out of it altogether.

The **10%**, **20%** and **30%** buttons fill the Scenario column with the published scenarios, which move that many percentage points from the fully vaccinated stratum into the unvaccinated one while holding the partially vaccinated strata fixed. Because only two strata move and the risks are constants, the excess is exactly linear in the shift magnitude.

The published shares (13.9% unvaccinated, 15.3% partially vaccinated, 70.7% fully vaccinated) sum to 99.9% because of rounding. The app reports each column's sum but does not correct it: auto-normalising would leave the app unable to reproduce the letter.

### The partially vaccinated stratum

The app carries **one** partially vaccinated stratum whose risks are the share-weighted average of the two levels, with the weight exposed as a single sidebar parameter, *One dose, % of partially vaccinated*. The two risk cells for that row are shown read-only in the grid because they are derived rather than entered.

### Risk-difference sensitivity

Three buttons set the full-series risks so that the risk difference against unvaccinated equals a confidence limit or the point estimate from Butler et al. — Table 1 cell `E18`, −0.40 (−0.50, −0.31) for hospitalization, and Table 2 cell `E59`, −1.22 (−1.43, −1.00) for ED visits. Both risks move together, and the unvaccinated risk is read from the grid rather than a constant, so an edited reference is honoured.

| Button | Published risk difference | Full-series risk applied | Excess, 30% scenario |
| --- | --- | --- | --- |
| Most Conservative | −0.31 / −1.00 | 0.57 / 3.36 | 3,369 hosp, $79.4M |
| Best Estimate | −0.40 / −1.22 | 0.47 / 3.15 | 4,456 hosp, $103.5M |
| Least Conservative | −0.50 / −1.43 | 0.38 / 2.93 | 5,434 hosp, $125.7M |

The first column is Butler et al.'s reported figures throughout. For the two confidence limits the applied risk follows from them exactly (`0.88 − 0.31 = 0.57`). For the point estimate it does not, and that is the source's own rounding: `0.88 − 0.40` is 0.48, not the published 0.47.

*Conservative* follows the convention of naming the assumption least favourable to the claim being advanced: the smallest protective effect the data support yields the smallest projected excess, which is the direction consistent with the letter's framing of its figures as minimum estimates.

**Best Estimate** therefore restores the published *risks* rather than applying the published *risk difference*. Differencing 0.47 and 0.88 gives −0.41, and 3.15 and 4.36 gives −1.21 — both 0.01 from the reported values, because the paper rounds the risks and the difference independently. Restoring the risks is what makes the button a no-op and keeps the app reproducing the letter; applying −0.40 would silently move the full-series risk to 0.48.

That contrast is the one Butler et al. actually estimated and bootstrapped, and because the scenario moves people strictly between the full-series and unvaccinated strata, the projected excess is exactly linear in it. A bound on the risk difference therefore maps directly onto a bound on the excess, with no further assumption. At the 30% scenario this gives roughly $79M to $126M around a $103.5M point estimate.

Two caveats. Because the buttons change the full-series risk, they also move the baseline — 70.7% of the cohort sits in that stratum — so the relative-excess percentages shift as well; the interval is not a pure perturbation of the excess. And taking the hospitalization and ED limits together assumes the two err in the same direction, which overstates the width of a joint interval. Present it as a pre-specified bounding analysis rather than a 95% confidence interval.


## Parameter sources

| Parameter | Value | Source |
| --- | --- | --- |
| Annual U.S. births | 3,622,673 | CDC Vital Statistics Rapid Release No. 38 (provisional 2024) |
| Uptake distribution | 13.9 / 15.3 / 70.7 % | Sederdahl et al. *Pediatrics* 2019 |
| One dose, % of partially vaccinated | 33.390564 | Person-time ratio in Butler et al. 2021 Table 1, 162196/(162196+323558) |
| Two-year hospitalization risks | 0.88 / 0.673442 / 0.47 % | Butler et al. *Epidemiology* 2021, Table 1; middle value is the weighted blend of 0.80 and 0.61 |
| Two-year ED visit risks | 4.36 / 4.343528 / 3.15 % | Butler et al. *Epidemiology* 2021, Table 2; middle value is the weighted blend of 4.57 and 4.23 |
| Risk difference, full series vs unvaccinated | −0.40 (−0.50, −0.31) hosp; −1.22 (−1.43, −1.00) ED | Butler et al. 2021, Table 1 `E18` and Table 2 `E59`; drives the vaccine effectiveness buttons |
| Cost per hospitalization (direct) | \$19,251.56 | Karve et al. 2014, CPI-inflated to January 2025 |
| Cost per ED visit (direct) | \$781.83 | Karve et al. 2014, CPI-inflated to January 2025 |
| Indirect cost per episode | \$423.78 | Two days of median weekly earnings (BLS CPS 2023, $1,117/wk over a 7-day week) plus $104.64 median out-of-pocket costs, rounded to cents |

The published 95% confidence limits on the individual risks are retained in `rv_groups()` and `rv_scalars()` as `_lo`/`_hi` columns. Nothing consumes them: the sensitivity analysis uses `rv_rd_bounds()` on the full-series contrast instead, for the reasons given above. The partially vaccinated row carries `NA` bounds deliberately.

Two notes on the indirect cost that belong in any methods write-up. The $104.64 of out-of-pocket items is from Widdowson et al., CPI-inflated, but Widdowson's own forgone-earnings figure ($118/day in 2004, $202.40 inflated to 2025) is *excluded* and replaced by the BLS calculation — reasonable, since 2023 BLS data are fresher and using both would double-count, but not what the citation implies. And dividing median weekly earnings by seven yields a notional $159.57/day that no one actually forgoes; BLS reports earnings for full-time workers over a five-day week, so a lost workday is nearer $223.40. The five-day denominator would raise the indirect cost to $551.44 and the 30% estimate to about $105.8M. The current choice errs downward, consistent with the letter's framing of these as minimum estimates.

All four population and cost parameters are sliders. **The three cost sliders must keep `step = 0.01`.** ionRangeSlider rounds a value to the decimal count implied by `step`, so an integer step flattens `19251.56` to `19252` on both initial render and reset — that is what once turned `c_indirect` into `424` and stopped the app reproducing the spreadsheet. Two decimals is safe only because every cost default is now a whole number of cents. Verified in a browser rather than assumed: any change to these steps needs the same check, because a value that survives `testServer` can still be rounded by the widget.

## The no-harm constraint

No vaccinated stratum may carry a higher risk than the unvaccinated. Without it, entering such a value makes the projection incoherent rather than merely pessimistic: the excess turns negative and the app reports that withdrawing vaccination *prevents* encounters. `rv_clamp_harm()` caps each vaccinated stratum at the unvaccinated risk for both outcomes and names any cell it altered, which the app shows above the results.

The constraint is applied to the inputs, not inside `rv_project()`, which stays a pure calculator — this keeps the algebraic identities the tests rely on intact.

It can bind on a published estimate. Butler et al. put the one-dose RV5 two-year ED risk at 4.57% against 4.36% unvaccinated — a point estimate in the harmful direction, with a confidence interval spanning no effect. The blended partial risk crosses 4.36% once the one-dose share passes **38.24%**, so raising that weight above the published 33.39% triggers the cap. At the published values the constraint is inactive and changes nothing.

tpatient care, which is the binding constraint rather than the arithmetic.
