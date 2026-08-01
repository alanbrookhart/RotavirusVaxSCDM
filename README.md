# Rotavirus SCDM Sensitivity Analysis

An interactive sensitivity analysis accompanying Butler AM, Panozzo CA, Boutzoukas AE, Brookhart MA, *"Rotavirus Vaccination: Impact of New Recommendation"* (research letter, JAMA Pediatrics, under revision).

The application lets a reader vary every parameter and assumption underlying the published projection — annual births, the vaccination uptake distribution, the two-year risks of AGE-related hospitalization and emergency department visits, the per-episode unit costs, and the magnitude of the shift from routine to shared clinical decision-making — and see immediately how the projected excess burden and expenditures respond.

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

Two-year cumulative incidences come from Butler et al. (*Epidemiology* 2021;32:598–606), estimated with inverse probability of censoring weighting in a commercially insured birth cohort. The scenario moves a specified percentage of the birth cohort from the fully vaccinated to the unvaccinated stratum, holding the partially vaccinated strata fixed; the split of partially vaccinated children into one- and two-dose RV5 recipients is fixed at the person-time ratio in Butler et al. Table 1 (33.4% / 66.6%).

Because only two strata move and the risks are constants, the excess is exactly linear in the shift magnitude. This is worth keeping in mind when reading the sensitivity output: the interesting nonlinearity lies not in the shift but in how the excess scales with the risk difference between the unvaccinated and fully vaccinated strata.

Estimates account for direct effects of vaccination only. No indirect (herd) protection is assumed, consistent with the letter, so the projections should be read as a lower bound on the excess burden.

### Uptake can be specified two ways

The **Shift** slider reproduces the published scenarios (10%, 20%, 30% of the cohort moving from fully vaccinated to unvaccinated). Alternatively, the three uptake shares under **Assumptions → Vaccination uptake** can be set directly to any distribution of interest.

The published shares (13.9% unvaccinated, 15.3% partially vaccinated, 70.7% fully vaccinated) sum to 99.9% because of rounding. The app leaves this uncorrected by default so that it reproduces the source spreadsheet exactly, and flags it; a checkbox rescales the shares to sum to 100%.

## Verification

`tests/test-model.R` checks the R implementation against specific cells of `docs/RV spreadsheet.xlsx`. All six primary targets reproduce to the cent:

| Quantity | Model | Spreadsheet |
| --- | --- | --- |
| Baseline hospitalizations (K19) | 20,201.71 | 20,201.71 |
| Baseline ED visits (K60) | 126,708.41 | 126,708.41 |
| Baseline expenditures (W23) | $550,236,945.15 | $550,236,945.15 |
| Excess expenditures, 10% shift (X24) | $34,508,431.45 | $34,508,431.45 |
| Excess expenditures, 20% shift (X25) | $69,016,862.91 | $69,016,862.91 |
| Excess expenditures, 30% shift (X26) | $103,525,294.36 | $103,525,294.36 |

### One discrepancy worth resolving before resubmission

The letter reports **\$32.0 million** for a 10% shift and **\$103.5 million** for a 30% shift. These are not on the same footing:

- \$32.0 million is the excess under a **direct medical** perspective (the model gives \$32,021,364).
- \$103.5 million is the excess under a **societal** perspective (direct plus indirect costs).

The corresponding matched figures are \$34.5 million (10% shift, societal) and \$96.1 million (30% shift, direct medical). Since the Methods section states that costs were defined from a societal perspective, the 10% figure appears to be the one that needs updating, to \$34.5 million. The app's cost-perspective control reproduces either convention.

## Parameter sources

| Parameter | Value | Source |
| --- | --- | --- |
| Annual U.S. births | 3,622,673 | CDC Vital Statistics Rapid Release No. 38 (provisional 2024) |
| Uptake distribution | 13.9 / 15.3 / 70.7 % | Sederdahl et al. *Pediatrics* 2019 |
| Two-year hospitalization risks | 0.88 / 0.80 / 0.61 / 0.47 % | Butler et al. *Epidemiology* 2021, Table 1 |
| Two-year ED visit risks | 4.36 / 4.57 / 4.23 / 3.15 % | Butler et al. *Epidemiology* 2021, Table 2 |
| Cost per hospitalization (direct) | \$19,251.56 | Karve et al. 2014, CPI-inflated to January 2025 |
| Cost per ED visit (direct) | \$781.83 | Karve et al. 2014, CPI-inflated to January 2025 |
| Indirect cost per episode | \$423.78 | Two days of median weekly earnings (BLS CPS 2023) plus out-of-pocket costs |

Tornado bounds use published 95% confidence limits where available and stated plausible ranges otherwise; both appear in the app under **Model & sources**.

## Possible extensions

Three features were scoped out of this draft but are straightforward to add, since `rv_project()` already takes the relevant arguments or is easily generalized:

- **Probabilistic sensitivity analysis.** Draw risks from their reported confidence limits and costs from lognormal distributions, and report medians with 95% intervals. Note that the bootstrap confidence intervals in Butler et al. are marginal, so treating the four stratum-specific risks as independent will overstate the width of the resulting interval.
- **Indirect (herd) protection.** A multiplier on risk in the unvaccinated stratum, addressing the first stated limitation. Whether this widens or narrows the excess depends on whether the multiplier is held fixed or allowed to scale with coverage, which is the substantively interesting question.
- **Multi-cohort projection.** `rv_project(cohorts = n)` already implements this; it needs only a control in the sidebar (one is present but could be surfaced more prominently).
