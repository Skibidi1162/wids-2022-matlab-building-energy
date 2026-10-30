# WiDS Datathon 2022: building energy prediction in MATLAB

Predict annual building energy use intensity (`site_eui`) using building characteristics, weather, and earlier readings from matching building groups. All reported model training and inference use **MATLAB with Statistics and Machine Learning Toolbox**.

The selected method predicts the change from a group's latest earlier EUI with LSBoost. Buildings without usable history receive a 50/50 average of LSBoost and random-forest predictions.

## Results

| Experiment | Historical pooled RMSE |
| --- | ---: |
| Tuned LSBoost, 59 baseline predictors | 41.8175 |
| Random forest | 42.6302 |
| Bagged trees | 43.1378 |
| Ridge regression | 51.8280 |
| Approximate Gaussian kernel | 67.4925 |
| Neural network, 100 iterations | 96.5427 |
| 50/50 LSBoost and random forest | 41.1337 |
| Latest earlier EUI with fallback | 36.1865 |
| LSBoost with history, direct target | 35.2257 |
| **LSBoost with history, change target and fallback** | **34.9346** |

Historical validation trains on years 1â€“3 to predict year 4 and on years 1â€“4 to predict year 5. Pooled RMSE is `sqrt(total squared error / 31254 validation rows)`. The selected method reduces RMSE by **16.46%** relative to tuned baseline LSBoost. These are model-selection folds. Year 6 was examined in earlier feature experiments, so it is not an untouched independent holdout.

The full-data MATLAB refit received **public RMSE 19.545** and **private RMSE 21.552** in a successful late Kaggle submission on 30 October 2026. Kaggle scores evaluate different rows from historical validation and are not a direct before/after improvement. Late submissions do not alter the closed official leaderboard. See [the receipt](kaggle_submission/SUBMISSION_RESULT.md).

![MATLAB model-family comparison](model_comparison_charts/01_model_families.png)

![Effect of building-history features](model_comparison_charts/02_building_history.png)

LSBoost was selected from eight configurations; the alternative families had a compact initial screen. Both neural-network budgets hit their iteration limits. The 1,000-iteration follow-up scored 297.2084. Kernel diagnostics do not establish convergence on both folds. These trials do not establish the best achievable score for every family.

## Dataset

Download the inputs yourself from [WiDS Datathon 2022 on Kaggle](https://www.kaggle.com/competitions/widsdatathon2022/data), subject to its access requirements and rules:

```text
data/
  train.csv             # 75,757 building-year records, years 1â€“6
  test.csv              # 9,705 records, year 7, hidden target
  sample_solution.csv   # submission IDs and expected schema
```

The data cover commercial and residential buildings, 60 facility types, and seven anonymized state codes. The repository includes code, aggregate metrics, and charts. It excludes raw competition data, row-level predictions, fitted model binaries, credentials, and account screenshots. Downloaded data remain governed by the competition's terms.

## Run the selected model

The local workflow was tested on **MATLAB R2026b on Windows** with Statistics and Machine Learning Toolbox. Current local runners use the Windows .NET file API for SHA256. No Parallel Computing Toolbox or GPU is required for these local fits. MATLAB and toolbox licenses are not included.

From the repository root:

```matlab
setup_wids_project;
% Optional when the CSV files are elsewhere:
% setenv('WIDS_DATA_DIR','D:\datasets\widsdatathon2022');
cd kaggle_submission
run_wids_submission("prepare");
run_wids_submission("residual");
run_wids_submission("boost");
run_wids_submission("forest");
run_wids_submission("export");
```

Run each stage separately. Matching successful checkpoints are reusable. Export generates `wids_history_residual_submission.csv` in sample-ID order and checks 9,705 unique IDs, two columns, finite values, exact numeric readback, and data/model/source identity. This code does not log in to Kaggle or submit files automatically.

The residual model uses 300 trees, learning rate 0.05, maximum 31 splits, minimum leaf size 5, and seed 42. It fits 49,384 labeled rows with earlier history. Both fallback models fit all 75,757 labeled rows. Of the test rows, 9,067 have matching history and 638 use the fallback. No target log transform, clipping, or calibration is applied.

## History features and leakage controls

Infer a group using the **raw** tuple `State_Factor`, `building_class`, `facility_type`, `floor_area`, and `year_built`, before median imputation. This is an identity proxy, not a verified unique physical-building identifier.

The eight features are history availability, count of earlier observed years, latest EUI, equal-year mean EUI, second-most-recent EUI, time gap since latest EUI, latest nonmissing energy-star rating, and rating change. Average duplicate building-year values before aggregation. Six history missingness flags expand the 59-predictor baseline to 73 columns. Numeric inputs remain on their original scales for the final tree models.

A row at year t can use only fitting-label history from years earlier than t. Fit preprocessing and history-value replacements on training rows only. The history helper accepts validation/test tables without a target column. The synthetic check exercises duplicate averaging, temporal gaps, and invariance to same-year, future-year, and query labels.

## Reproduce comparisons and charts

After `setup_wids_project`, run the following workflows from their folders:

1. `local_tuning/run_local_tuning`: regenerate LSBoost checkpoints and aggregate scores.
2. `local_model_comparison/run_model_comparison`: fit five alternative CPU configurations on both folds. Then run `verify_model_comparison` and `evaluate_wids_blends`.
3. `local_model_comparison/check_building_history_logic`, `run_building_history_case(4)`, `run_building_history_case(5)`, and `summarize_history_results`: reproduce the history comparison.
4. `model_comparison_charts/create_model_comparison_charts`: redraw the supplied aggregate results in MATLAB, exporting PNG, SVG, FIG, and CSV locally.

Pretrained checkpoints are intentionally absent. Run tuning before comparison verifiers or history experiments that depend on L07. The optional longer network uses `run_longer_network_case(4)` and `(5)`.

Public copies use configurable data paths and fresh checkpoint signatures. Their verifier references point to the published current tuning sources. Previously recorded CSV scores are historical evidence; regenerated model objects require new computation and can differ across MATLAB releases.

## Repository layout

| Folder | Contents |
| --- | --- |
| `kaggle_submission` | Full-data staged MATLAB training and prediction export |
| `local_tuning` | Eight LSBoost configurations and recorded metrics |
| `local_model_comparison` | Model families, history experiments, verification, and results |
| `model_comparison_charts` | MATLAB plotting code and presentation charts |
| `feature_experiments` | Earlier feature engineering and ablation experiments |
| `nscc` | CPU MATLAB benchmark prototype with Python job orchestration |

The NSCC prototype has not run remotely. Its Python code handles packaging, scheduler-script preparation, and aggregation; model fitting remains in MATLAB. See its README before use.

## Sources

- [WiDS Datathon 2022](https://www.kaggle.com/competitions/widsdatathon2022)
- [MathWorks building-regression tutorial](https://github.com/mathworks/predicting-building-energy-consumption)
- [First-place solution](https://www.kaggle.com/competitions/widsdatathon2022/writeups/zujm-first-place-solution)
- [Second-place solution](https://www.kaggle.com/competitions/widsdatathon2022/writeups/dihydrogen-oxide-second-place-solution)
- [Third-place solution](https://www.kaggle.com/competitions/widsdatathon2022/writeups/gradient-boosted-math-ladies-third-place-solution)

The leading solutions motivated the history approach. This project implements its own MATLAB experiments and does not reproduce every winning-team technique. Original third-party data and tutorial assets are not redistributed here.
