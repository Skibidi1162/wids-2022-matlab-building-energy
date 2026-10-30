# Feature ablation and temporal stability

Recommendation: start the next model-tuning stage with the **59-predictor cleaned baseline**. The six-feature alternative has inconsistent benefits across years. Keep the full alternative as a challenger, given its earlier year-6 result; this is a provisional selection for tuning, not a final generalization claim.

## Controlled experiment

- Single-feature ablation: fit years 1â€“4 (35,000 rows), validate on year 5 (18,308 rows).
- Refitted construction-year and Energy Star medians, category vocabularies, facility-area medians, and facility/state vocabularies using the fitting rows only.
- The inner construction-year median is 1946, compared with 1950 when fitting on years 1â€“5. Energy Star median is 66.
- Same model for every run: LSBoost, 200 trees, learning rate 0.05, maximum 31 splits, minimum leaf size 20, all predictors eligible, seed 42.
- Target remains the original `site_eui`; `Year_Factor` is excluded from predictors.
- No new experiments fitted on year 6 or used Kaggle test labels.

## Single-feature ablation on year 5

Delta is relative to the full six-feature bundle. Negative delta means removal improved RMSE on this split.

| Experiment | Predictors | RMSE | MAE | Delta RMSE |
|---|---:|---:|---:|---:|
| Cleaned baseline | 59 | 42.37393 | 24.71232 | -3.31124 |
| All six additions | 65 | 45.68518 | 26.50003 | 0 |
| Remove relative floor area | 64 | 45.47495 | 26.15904 | -0.21023 |
| Remove facility Ã— state | 64 | 42.98533 | 25.44380 | -2.69985 |
| Remove heating share | 64 | 45.89852 | 26.66083 | +0.21334 |
| Remove monthly temperature spread | 64 | 45.26299 | 26.16719 | -0.42218 |
| Remove severe-cold share | 64 | 45.68518 | 26.50003 | 0 |
| Remove extreme-heat share | 64 | 45.74404 | 26.53393 | +0.05886 |
| Combined smaller bundle: heating share + extreme-heat share | 61 | 42.40500 | 24.75709 | -3.28017 |

The smaller bundle was trained explicitly after the single-drop tests; individual removal effects were not assumed to add together. It is only 0.073% worse than baseline on year 5, providing no measured improvement there. Removing severe-cold share produced identical year-5 predictions in this run; this does not establish that the feature is universally useless.

## Earlier-year stability check

Because the initial year-6 comparison favored the full bundle but the year-5 ablation did not, one bounded additional comparison used years 1â€“3 (22,054 rows) to predict year 4 (12,946 rows), again refitting preprocessing.

| Feature set | Year-4 RMSE | Year-5 RMSE | Pooled RMSE | Pooled MAE |
|---|---:|---:|---:|---:|
| Cleaned baseline | 43.14590 | 42.37393 | **42.69539** | **24.56340** |
| All six additions | **42.82554** | 45.68518 | 44.52295 | 25.06640 |
| Heating share + extreme-heat share | 43.17612 | 42.40500 | 42.72610 | 24.59390 |

Pooled RMSE is the square root of the total squared validation error divided by the total 31,254 validation records, rather than the arithmetic mean of the two RMSEs. These historical checks inform selection; their pooled score is not a final independent test score.

The full bundle improves year-4 RMSE by about 0.74% but worsens year-5 RMSE by about 7.81%. The smaller bundle is essentially tied with baseline on both checks. The previous, already-inspected year-6 result remains 39.08815 for the full alternative versus 42.64296 for baseline. Those scores used a different fitting history and validation year.

## Facility/state coverage

Year 5 contains 3,371 rows (18.4%) with facility/state combinations absent from years 1â€“4. Subgroup scores reuse saved predictions and require no new models.

| Year-5 subgroup | Rows | Baseline RMSE | Full-bundle RMSE | Without facility Ã— state RMSE | Smaller-bundle RMSE |
|---|---:|---:|---:|---:|---:|
| Known combinations | 14,937 | 36.145 | 37.051 | 36.623 | 36.295 |
| Unseen combinations | 3,371 | 62.949 | 72.473 | 63.968 | 62.680 |

The unseen combinations account for much of the full bundle's deterioration, but not all: its RMSE is also worse among known combinations. Coverage changes with the year split, so the interaction cannot be labeled universally harmful from this experiment.

## Checks and saved artifacts

- Changing year-5 inputs and targets cannot change fitted cleaning parameters, facility mappings, or fitting features.
- All model predictions are finite. Targets are unchanged, and all models use the same rows within each split.
- Existing feature-generation scripts and the earlier comparison models are preserved.
- `wids_selected_baseline_features.csv` lists the 59 baseline predictors for the next tuning stage.
- `wids_ablation_confirmed_results.csv`, `wids_ablation_subgroups.csv`, `wids_feature_stability.csv`, and `wids_feature_pooled_results.csv` contain the numeric results.

To reproduce from the Hackathon folder:

```matlab
run_wids_ablation_study
```

The scripts retain the compact fitted models and predictions in the MATLAB workspace. Subsequent tuning should use historical validation splits and compare the baseline with the full bundle under an equal tuning budget.
