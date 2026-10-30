# MATLAB model comparison results

The best tested configuration is **MATLAB LSBoost residual regression with earlier building history**, with pooled validation RMSE **34.93465**. This is **16.46% lower** than the previous tuned LSBoost model (41.81750), and **15.07% lower** than the new boost/forest ensemble (41.13375). All model training and history feature construction used MATLAB and Statistics and Machine Learning Toolbox.

## Comparable validation results

| Configuration | Year 4 RMSE | Year 5 RMSE | Pooled RMSE |
| --- | ---: | ---: | ---: |
| **History residual LSBoost + no-history fallback** | **30.18767** | **37.93448** | **34.93465** |
| LSBoost with history features, direct EUI target | 32.05017 | 37.30845 | 35.22573 |
| Latest earlier EUI + no-history fallback | 31.28105 | 39.28734 | 36.18653 |
| 50/50 tuned LSBoost + random forest | 41.76533 | 40.68122 | 41.13375 |
| 75/25 tuned LSBoost + random forest | 41.37982 | 41.07541 | 41.20177 |
| Previous tuned LSBoost L07 | 41.43553 | 42.08551 | 41.81750 |
| Random forest RF100 | 43.80010 | 41.78311 | 42.63017 |
| Bagged trees BAG100 | 43.97636 | 42.53483 | 43.13778 |
| Ridge regression RIDGE001 | 53.52654 | 50.59259 | 51.82804 |
| Approximate Gaussian kernel KERNEL1024 | 64.10805 | 69.78677 | 67.49253 |
| Neural network, 100 iterations | 121.70662 | 73.73579 | 96.54269 |
| Neural network, 1,000 iterations | 440.69122 | 116.04148 | 297.20844* |

*The exact longer-network score is stored in the CSV; both network budgets reached their iteration limits. Their results do not establish the best achievable neural-network performance. The kernel's returned diagnostics also do not establish convergence on both folds. Ridge met its coefficient-tolerance criterion; both bagged ensembles completed all 100 trees. These are selected configurations, not exhaustive family comparisons. The standalone families were initially screened with one configuration each, while L07 had already been tuned.

## What the selected model does

1. Infer a building group from the raw tuple State_Factor, building_class, facility_type, floor_area, and year_built. Keep raw missing/zero values distinct from imputed values. This is a proxy identity, not a verified building identifier.
2. Average duplicate readings within each earlier building-year. Construct eight features: history availability, number of observed earlier years, latest EUI, equal-year mean EUI, previous observed EUI, gap since the latest observed EUI, latest observed rating, and current-minus-earlier rating.
3. Fit missing-value replacements on fitting rows and add six history missingness indicators. The resulting model uses 73 predictor columns: the frozen 59 baseline predictors, eight history features, and six indicators.
4. Train LSBoost on rows with history to predict current EUI minus latest earlier EUI. Use 300 trees, learning rate 0.05, maximum 31 splits, minimum leaf size 5, and seed 42. Add the predicted change to the latest earlier EUI.
5. For rows without history, use the existing 50/50 L07/random-forest ensemble.

Pooled MAE is **19.09050**. Matched-history rows have RMSE **22.93125** (22,760 validation rows); rows without history have RMSE **55.51219** (8,494 rows). The unmatched group is the clearest remaining weakness. The direct history model performs better on year 5; residual boosting wins the specified pooled-RMSE objective.

## Evidence and limitations

Year 4 uses 22,054 fitting and 12,946 validation rows; year 5 uses 35,000 fitting and 18,308 validation rows. History coverage is 78.21% and 69.01%, respectively. Pooled RMSE is calculated from all 31,254 validation squared errors, not by averaging fold RMSE values. Cleaning, category vocabularies, scaling where applicable, and history imputation are fitted without validation labels. A row at year t can use only fitting-label history from years earlier than t.

The synthetic history checks passed duplicate-year averaging, temporal gaps, and invariance to query/current/future targets. Saved predictions for the reference, alternative models, and all six history model/fold cases were recomputed against original IDs and labels; saved SSE/SAE and preprocessing/code provenance were checked. MATLAB Code Analyzer reported no issues in the new history files. No outlier deletion, EUI capping, pseudo-labeling, or target-log transformation was introduced.

The full training-data match audit found earlier history for **9,067/9,705 competition test rows (93.43%)**. There are 903 duplicate training key-year groups, 869 with differing EUI readings; 68 test rows have a matched group with conflicting earlier duplicate labels. These are audit flags, not proof that the records represent different physical buildings. Earlier duplicate readings are averaged rather than silently discarded.

These are historical model-selection scores, not an independent final-test estimate. Year 6 was examined in previous feature experiments. No competition targets were used. This benchmark folder contains the two validation-fold models. A subsequent full-data MATLAB refit was successfully submitted to Kaggle on 30 October 2026: public RMSE 19.545 and private RMSE 21.552. See the [submission receipt](../kaggle_submission/SUBMISSION_RESULT.md); it evaluates different test rows from this benchmark.

## Saved artifacts and next MATLAB work

- results/history_comparison_results.csv: exact pooled and subgroup scores.
- results/HISTORY_year4.mat and HISTORY_year5.mat: models, predictions, row IDs, preprocessing, fallback identity, and source provenance. The selected estimator is models.HISTORY_RESIDUAL within each file.
- results/comparison_with_boosted_reference.csv and blend_comparison_results.csv: other model families and blends.
- results/verified_prediction_metrics.csv and solver_diagnostics.txt: verification and optimization diagnostics.
- results/test_building_match_audit.mat and building_key_duplicate_audit.csv: matching and duplicate audits.
- SELECTED_MODEL.json: current selected configuration and validation results.

The next search should tune MATLAB's history residual/direct ensembles and improve the unmatched-building fallback. On NSCC, confirm full MATLAB, Statistics and Machine Learning Toolbox, licenses, and allocated CPU resources before submitting independent configuration/fold jobs. The [leading-solution review](TOP_SOLUTIONS.md) supplies method ideas; implementation remains in MATLAB.
