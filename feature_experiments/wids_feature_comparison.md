# WiDS feature comparison

The alternative feature bundle produced the lowest year-6 validation error in this first controlled experiment. This is a feature comparison with fixed model settings, not a tuned final model.

| Feature set | Predictors | Validation RMSE | Validation MAE | Validation RÂ² |
|---|---:|---:|---:|---:|
| Cleaned baseline | 59 | 42.64296 | 21.25319 | 0.44065 |
| Existing proposal | 66 | 42.83004 | 21.43449 | 0.43574 |
| Alternative proposal | 65 | 39.08815 | 19.63242 | 0.53002 |

Alternative RMSE improved by 8.34% relative to baseline and 8.74% relative to the existing proposal. Lower RMSE and MAE are better. All errors are measured on the original `site_eui` scale.

## Controlled setup

- Fit on years 1â€“5: 53,308 rows.
- Validate on year 6: the same 22,449 rows for every model.
- Identical cleaning, target values, random seed (42), and model settings across branches.
- MATLAB `fitrensemble`, LSBoost, 200 trees, learning rate 0.05, maximum 31 splits per tree, minimum leaf size 20, all predictors eligible at each split.
- Remove `Year_Factor` from all branches.
- Train directly on `site_eui`; no response logarithm or prediction clipping.
- Kaggle year-7 test records are not scored because their answers are withheld.

## Alternative features

| Feature | Definition | Hypothesis |
|---|---|---|
| Relative floor area | Floor area / fitting median area for the facility type | Buildings may behave differently when unusually large or small for their use type |
| Facility Ã— state | Combined categorical facility type and state code | Usage and location may interact |
| Heating share | HDD / (HDD + CDD + 1) | Distinguishes heating-dominated from cooling-dominated climates |
| Mean monthly temperature spread | Average of monthly maximum minus monthly minimum, across 12 months | Summarizes within-month temperature spread, rather than seasonal averages |
| Severe-cold share | Days below 10Â°F / max(days below 30Â°F, 1) | Separates severe cold from generally cold weather |
| Extreme-heat share | Days above 100Â°F / max(days above 80Â°F, 1) | Separates extreme heat from generally hot weather |

All original baseline predictors remain available. These six features do not use energy-use target values. Facility medians and interaction vocabularies are learned only from fitting rows. Unseen facility types use the overall fitting median area; unseen facilityâ€“state pairs use an unknown category.

The existing proposal keeps its seven added features, including smoothed facility log-EUI encoding. Training encodings exclude each training year in turn. Year-6 encodings use years 1â€“5 only.

## Verification and limits

- Checked nested temperature counts and monthly maximum/minimum ordering before constructing ratios and spreads.
- Changing all fitting and validation targets leaves the alternative predictors and preparation parameters unchanged.
- All predictor schemas match across fitting, validation, and Kaggle data; numeric features and validation predictions are finite.
- The result applies to this model configuration and this year split. It does not establish that every alternative feature helps individually, or that the same ranking holds for other model families.
- Further model tuning should use an inner time split (such as years 1â€“4 â†’ year 5), with preparation refitted inside that split. Do not randomly repartition precomputed target-encoded tables and treat the resulting score as independent validation.

## Reproduce

All companion scripts are saved in `<project-root>`.

```matlab
cd('<project-root>')
compare_wids_features
```

The comparison script reruns cleaning, builds both feature branches, trains the three models, and writes `wids_feature_comparison.csv` beside the scripts. Trained models and validation predictions remain in the MATLAB workspace as `widsComparisonModels` and `widsComparisonPredictions`.
