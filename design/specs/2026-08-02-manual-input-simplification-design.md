# Design: manual-entry simplification of the Rotavirus SCDM app

**Date:** 2026-08-02
**Status:** approved, pending implementation plan

## Goal

Let the reader type the uptake percentages and the risk rates for each
vaccination group directly, and cut the app back to a single-screen calculator.

Today the app expresses a scenario indirectly: three uptake sliders establish a
baseline, and a separate "shift" slider moves N percentage points from fully
vaccinated to unvaccinated. That is two concepts — a distribution and a
transformation of it — where one will do. Replacing the shift with a typed
Scenario column removes the abstraction and, as a side effect, lets the app
express scenarios the current model cannot, such as children moving into partial
rather than out of vaccination altogether.

## Decisions

| Question | Decision |
| --- | --- |
| Scenario representation | Two typed columns (Current %, Scenario %), plus 10/20/30% prefill buttons |
| One-way sensitivity and Tornado tabs | Dropped |
| Controls kept | Annual births, unit costs, cost-perspective toggle, cohorts |
| Births and unit costs | Remain sliders, not typed |
| Rescale-to-100% checkbox | Dropped, replaced by a live column-sum readout |
| Grid implementation | Hand-built HTML table of `numericInput`s |
| Displayed precision of the 1-dose/2-dose split | Six decimals |

The Shinylive deployment constrains the grid implementation. `app.R` depends
only on `shiny` and `bslib` because those ship with the Shinylive runtime; an
editable data grid (`DT`, `rhandsontable`, `reactable`) would add wasm packages
to an already 30–40 MB bundle, and the JS-heavy ones are unreliable under webR.
A `tags$table` with a `numericInput` per cell and labels suppressed in CSS keeps
the dependency profile unchanged while still reading as groups × quantities.

## Model API

`model.R` splits its single 15-row registry into three pieces, because group
quantities and scalar assumptions now behave differently in the UI.

```r
rv_groups()     # 4 rows x (id, label, share, risk_h, risk_e)
rv_scalars()    # births, c_hosp, c_ed, c_indirect -- sliders, so keep min/max/step
rv_scenarios()  # named list: "10%" / "20%" / "30%" -> scenario share vectors
rv_project(groups, scen_share, scalars, societal = TRUE, cohorts = 1)
```

The signature change is the substance of the redesign. `rv_project()` no longer
takes a `shift` and no longer computes a scenario; it is handed both share
vectors. Clamping, `shift_applied`, and the "requested shift exceeds the fully
vaccinated share" warning all disappear with it.

Removed entirely: `rv_oneway()`, `rv_tornado()`, `rv_outcome()`, and
`rv_outcome_choices()` — roughly 80 lines. `w_partial1` ceases to exist as a
parameter; its two strata are typed directly as rows.

The `low`/`high` bounds are **retained as data** even though nothing consumes
them in this revision. They are the published 95% confidence limits from Butler
et al. 2021 Tables 1 and 2, plus the stated plausible ranges for births and
costs — fifteen pairs transcribed by hand from the spreadsheet. A sensitivity
analysis is the agreed next piece of work, so dropping and re-transcribing them
would risk introducing a transcription error for no gain. They live as
`risk_h_lo`/`risk_h_hi`/`risk_e_lo`/`risk_e_hi` on `rv_groups()` and as
`low`/`high` on `rv_scalars()`.

Added: `excess$pct_cost`, so the app can display the expenditure percentages in
the letter's Figure 2 footnote d (6.3 / 12.5 / 18.9%), which it currently cannot.

### Default values

Shares and risks, by group:

| Group | Current % | Hosp. risk % | ED risk % |
| --- | --- | --- | --- |
| Unvaccinated | 13.9 | 0.88 | 4.36 |
| Partial RV5 (1 dose) | 5.108756 | 0.80 | 4.57 |
| Partial RV5 (2 doses) | 10.191244 | 0.61 | 4.23 |
| Full series | 70.7 | 0.47 | 3.15 |

Prefill scenario columns, matching spreadsheet rows J23–J26, J31–J34, J41–J44:

| Scenario | Unvax | Partial 1 | Partial 2 | Full |
| --- | --- | --- | --- | --- |
| 10% | 23.9 | 5.108756 | 10.191244 | 60.7 |
| 20% | 33.9 | 5.108756 | 10.191244 | 50.7 |
| 30% | 43.9 | 5.108756 | 10.191244 | 40.7 |

Scalars keep their present values and provenance, including `c_indirect` written
as the expression `1117 / 7 * 2 + 104.64`.

## UI

`page_navbar` drops to two tabs.

**Calculator** — the grid first, then the three value boxes (excess
hospitalizations, excess ED visits, excess expenditures), the baseline/scenario
bar charts, the per-group detail table, and the summary table. The sidebar keeps
the perspective radio, the cohorts box, the births slider, and the three
unit-cost sliders.

The "Excess burden by shift magnitude" plot is removed. It sweeps `shift` across
0–50% on the x-axis, and with the scenario typed as a column there is no longer
a single scalar to sweep. Nothing is lost analytically: the curve was exactly
linear by construction, since only two strata moved and the risks were constants.

**Model & sources** — retained unchanged in purpose. It holds the methods
narrative, parameter provenance, and the reproducibility note; that is
documentation rather than sensitivity analysis, so it is not in scope for the
cut.

The grid is a five-column table: group label, Current %, Scenario %, Hosp. risk
%, ED risk %. Sixteen `numericInput`s sit in `<td>` cells with labels suppressed.
Three small buttons under the Scenario column fill it from `rv_scenarios()`; a
Reset button restores every cell to the defaults above.

### Validation

A footer row shows each share column's sum, muted when within 0.05 of 100% and
amber otherwise. **It reports without correcting.** The published values
legitimately sum to 99.9% because of rounding, so auto-normalising would leave
the app unable to reproduce the letter.

Any blank or `NA` cell reads as 0 for computation, and a banner names the empty
cells. This is deliberate: silently substituting the default would fight the user
mid-typing, while the current code's unguarded arithmetic is what produces the
`need finite 'ylim' values` crash when the cohorts box is cleared. Births and
cohorts are additionally clamped to sensible floors.

## Precision

The 1-dose/2-dose split is a derived quantity that the spreadsheet carries to
full precision in cell `H16`; rounding it in code is what broke the regression
suite on 2026-08-02. Now that the number is displayed in an input box, its
precision is a UI decision. Measured against the spreadsheet's $550,236,945.15
baseline:

| Displayed default | Deviation | Effect on counts |
| --- | --- | --- |
| `5.10875628404501` | exact | none |
| `5.108756` | $0.43 | under 0.0001 encounters |
| `5.1088` | $66 | 0.003 hosp, 0.005 ED |
| `5.11` | $1,869 | 0.09 hosp, 0.15 ED |

Six decimals is the choice. Every deviation here is invisible in reported
results, so what is actually at stake is the README's verification table and its
claim of reproduction to the cent. Six decimals keeps every existing test
tolerance unchanged — the cost assertion stays at $1 — making the cosmetic gain
free.

A related trap, already verified as absent: `numericInput` and `sliderInput` do
**not** snap a fractional default to the `step` grid. Confirmed in a browser by
reading the live DOM, where `c_indirect` holds `423.782857142857` against
`step = 1`. Any future change to these defaults must be re-checked in the
browser, not only in `testServer`, because a value that survives the test but
snaps in the UI would make the app disagree with its own test suite.

## Testing

`tests/test-model.R` is rewritten around the new signature and keeps its job:
assert cells `K19`, `K60`, `W23`, and `X24`–`X26` from the published Current
column and each prefill Scenario column, and keep the direct-versus-societal
reconciliation that pins the letter's $32.0M against its $103.5M. The tornado
sanity block is removed.

Two checks are added:

- each prefill column equals the Current column with the published shift
  applied, guarding the new `rv_scenarios()` constants against transcription
  error;
- a blank cell yields 0 rather than an error.

Verification is not complete until the app has been driven in a real browser and
the rendered summary table read back, for the snapping reason above.

## Out of scope

- **Sensitivity analysis — deferred, not abandoned.** Agreed as the next piece
  of work after this revision lands. Its form is undecided; the retained
  `low`/`high` bounds are the input it will need, whatever shape it takes.
- Herd-protection modelling.
- The bar charts' missing "Scenario" tick label, a pre-existing base-graphics
  label collision.
- Documentation discrepancies found in review and reported separately: the
  letter's footnote d reads 18.9% where the source gives 18.8147%, and its
  Results text truncates counts rather than rounding them (1,400 for 1,485).

## Consequences

`model.R` loses roughly 80 lines, `app.R` roughly 120. The README needs its
Verification and Parameter-sources sections updated, and the sentence describing
the Shift slider replaced.

Reviewer #3's request that uncertainty be "incorporated into the projections for
sensitivity analysis" is unanswered by the app between this revision and the
follow-up. That gap is temporary and known, but if the revision is resubmitted
in the interim the response letter cannot point at the app for that comment.
