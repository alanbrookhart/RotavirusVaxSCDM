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

The Routine (pre-SCDM) and SCDM Scenario columns of the group grid are typed directly, so any pair of uptake distributions can be compared — including scenarios the published letter cannot express, such as children moving into partial vaccination rather than out of it altogether.

The **10%**, **20%** and **30%** buttons fill the SCDM Scenario column with the published scenarios, which move that many percentage points from the fully vaccinated stratum into the unvaccinated one while holding the partially vaccinated stratum fixed. Because only two strata move and the risks are constants, the excess is exactly linear in the shift magnitude.

Sederdahl's rounded shares — 13.9% unvaccinated, 15.3% partially vaccinated, 70.7% fully vaccinated — sum to 99.9%. The app carries **15.4%** partially vaccinated so the distribution totals 100%. That group is held fixed between the two uptake columns, so the correction cannot touch any excess estimate; it lands entirely in the baseline, raising it by $667,186, and every percentage the letter reports is unchanged at one decimal. Each column's running total is shown beneath the grid.

### The partially vaccinated stratum

The app carries **one** partially vaccinated stratum, matching the letter, with the two-year risks it reports: 0.67% for AGE-related hospitalization and 4.34% for AGE-related ED visits. Those are the share-weighted average of Butler et al.'s one-dose level (0.80%, 4.57%) and two-dose level (0.61%, 4.23%), taking 33.4% of the group as one-dose — the person-time ratio `162196/(162196+323558)` from Table 1.

That weight is **not** exposed as a control, deliberately. Person-time in an intermediate dose state is not the share of children who stop there: it is accrued mostly by children passing through one dose on the way to completing the series, so its relationship to the quantity we want is unclear in both size and direction. Rather than offer a knob whose calibration cannot be defended, the app takes the published figures as given.

Nothing is lost by combining the levels. Both are held fixed between the two uptake columns, so their contribution cancels in the difference and the projected excess is identical however the group is split — an algebraic identity, since the model is linear in the shares. `tests/test-model.R` asserts it against an explicit two-stratum build. The split moves only the baseline, by about 5% across the full range of the weight.

### Risk-difference sensitivity

Three buttons set the fully vaccinated risks so that the risk difference against unvaccinated equals a confidence limit or the point estimate from Butler et al. — Table 1 cell `E18`, −0.40 (−0.50, −0.31) for hospitalization, and Table 2 cell `E59`, −1.22 (−1.43, −1.00) for ED visits. Both risks move together, and the unvaccinated risk is read from the grid rather than a constant, so an edited reference is honoured.

| Button | Published risk difference | Fully vaccinated risk applied | Excess, 30% scenario |
| --- | --- | --- | --- |
| Most Conservative | −0.31 / −1.00 | 0.57 / 3.36 | 3,369 hosp, $79.4M |
| Best Estimate | −0.40 / −1.22 | 0.47 / 3.15 | 4,456 hosp, $103.5M |
| Least Conservative | −0.50 / −1.43 | 0.38 / 2.93 | 5,434 hosp, $125.7M |

The first column is Butler et al.'s reported figures throughout. For the two confidence limits the applied risk follows from them exactly (`0.88 − 0.31 = 0.57`). For the point estimate it does not, and that is the source's own rounding: `0.88 − 0.40` is 0.48, not the published 0.47.

*Conservative* follows the convention of naming the assumption least favourable to the claim being advanced: the smallest protective effect the data support yields the smallest projected excess, which is the direction consistent with the letter's framing of its figures as minimum estimates.

**Best Estimate** therefore restores the published *risks* rather than applying the published *risk difference*. Differencing 0.47 and 0.88 gives −0.41, and 3.15 and 4.36 gives −1.21 — both 0.01 from the reported values, because the paper rounds the risks and the difference independently. Restoring the risks is what makes the button a no-op and keeps the app reproducing the letter; applying −0.40 would silently move the fully vaccinated risk to 0.48.

That contrast is the one Butler et al. actually estimated and bootstrapped, and because the scenario moves people strictly between the fully vaccinated and unvaccinated strata, the projected excess is exactly linear in it. A bound on the risk difference therefore maps directly onto a bound on the excess, with no further assumption. At the 30% scenario this gives roughly $79M to $126M around a $103.5M point estimate.

Two caveats. Because the buttons change the fully vaccinated risk, they also move the baseline — 70.7% of the cohort sits in that stratum — so the relative-excess percentages shift as well; the interval is not a pure perturbation of the excess. And taking the hospitalization and ED limits together assumes the two err in the same direction, which overstates the width of a joint interval. Present it as a pre-specified bounding analysis rather than a 95% confidence interval.


## Parameter sources

| Parameter | Value | Source |
| --- | --- | --- |
| Annual U.S. births | 3,622,673 | CDC Vital Statistics Rapid Release No. 38 (provisional 2024) |
| Uptake distribution | 13.9 / 15.4 / 70.7 % | Sederdahl et al. *Pediatrics* 2019 (13.9 / 15.3 / 70.7); the partially vaccinated share carries a 0.1 correction so the distribution totals 100% |
| Two-year AGE-related hospitalization risks | 0.88 / 0.67 / 0.47 % | Butler et al. *Epidemiology* 2021, Table 1; middle value combines the one- and two-dose RV5 levels (0.80, 0.61) at the person-time split |
| Two-year AGE-related ED visit risks | 4.36 / 4.34 / 3.15 % | Butler et al. *Epidemiology* 2021, Table 2; middle value combines the one- and two-dose RV5 levels (4.57, 4.23) at the person-time split |
| Risk difference, full series vs unvaccinated | −0.40 (−0.50, −0.31) hosp; −1.22 (−1.43, −1.00) ED | Butler et al. 2021, Table 1 `E18` and Table 2 `E59`; drives the vaccine effectiveness buttons |
| Cost per hospitalization (direct) | \$19,252 | Karve et al. 2014, CPI-inflated to January 2025 (\$19,251.56), to the dollar |
| Cost per ED visit (direct) | \$782 | Karve et al. 2014, CPI-inflated to January 2025 (\$781.83), to the dollar |
| Indirect cost per episode | \$424 | Two days of median weekly earnings (BLS CPS 2023, $1,117/wk over a 7-day week) plus $104.64 median out-of-pocket costs (\$423.78), to the dollar |

The published 95% confidence limits on the individual risks are retained in `rv_groups()` and `rv_scalars()` as `_lo`/`_hi` columns. Nothing consumes them: the sensitivity analysis uses `rv_rd_bounds()` on the fully vaccinated contrast instead, for the reasons given above. The partially vaccinated row carries `NA` bounds deliberately.

Two notes on the indirect cost that belong in any methods write-up. The $104.64 of out-of-pocket items is from Widdowson et al., CPI-inflated, but Widdowson's own forgone-earnings figure ($118/day in 2004, $202.40 inflated to 2025) is *excluded* and replaced by the BLS calculation — reasonable, since 2023 BLS data are fresher and using both would double-count, but not what the citation implies. And dividing median weekly earnings by seven yields a notional $159.57/day that no one actually forgoes; BLS reports earnings for full-time workers over a five-day week, so a lost workday is nearer $223.40. The five-day denominator would raise the indirect cost to $551.44 and the 30% estimate to about $105.8M. The current choice errs downward, consistent with the letter's framing of these as minimum estimates.

Costs are carried as **whole dollars**, by decision, and the three cost sliders step by $1. **Their defaults must stay whole numbers.** ionRangeSlider rounds a value to the decimal count implied by `step`, so a fractional default against `step = 1` would display and return the rounded figure while the model held the exact one — the app would disagree with itself, and a reset would silently change the answer. Keeping default and step on the same grid is what prevents that, and it needs checking in a browser rather than only in `testServer`, since a value that survives the test harness can still be rounded by the widget.

Three deliberate departures separate this model from the spreadsheet: the whole-dollar costs, the two-decimal partially vaccinated risks the letter reports, and the 0.1 correction to the partially vaccinated share. Together they put the baseline **$330,548 above** the spreadsheet's, with the excess **0.008% above** its figures and the baseline counts higher by 5 hospitalizations and 138 ED visits. Nothing the letter reports moves: both printed figures stay $34.5M and $103.5M, and footnote d stays 6.3% and 18.8%. `tests/test-model.R` asserts exactly that — it compares the reported strings rather than a dollar bound, so a future change that pushed the rounding past reporting precision would fail rather than pass quietly. Its *Spreadsheet equivalence* block undoes all three — Karve's cents, the `1117/7` intermediate, the unrounded weighted average for the partially vaccinated, and the 15.3 share — and confirms all six cells (`K19`, `K60`, `W23`, `X24`–`X26`) reproduce exactly, which is the proof that those roundings are the only difference.

## The no-harm constraint

No vaccinated stratum may carry a higher risk than the unvaccinated. Without it, entering such a value makes the projection incoherent rather than merely pessimistic: the excess turns negative and the app reports that withdrawing vaccination *prevents* encounters. `rv_clamp_harm()` caps each vaccinated stratum at the unvaccinated risk for both outcomes and names any cell it altered, which the app shows above the results.

The constraint is applied to the inputs, not inside `rv_project()`, which stays a pure calculator — this keeps the algebraic identities the tests rely on intact.

It sits closer to binding than it looks. Butler et al. put the one-dose RV5 two-year ED risk at 4.57% against 4.36% unvaccinated — a point estimate in the harmful direction, with a confidence interval spanning no effect. The combined partially vaccinated ED risk of 4.34% clears the unvaccinated reference by only 0.02, so a partially vaccinated group weighted more heavily towards one dose would cross the constraint. At the published values it is inactive and changes nothing.

tpatient care, which is the binding constraint rather than the arithmetic.
