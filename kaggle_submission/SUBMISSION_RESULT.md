# Kaggle submission result

**Kaggle successfully scored the MATLAB submission.** The submission detail page reports Complete (after deadline).

| Evaluation | RMSE displayed by Kaggle |
| --- | ---: |
| Public score | **19.545** |
| Private score | **21.552** |

Verified on 30 October 2026, Asia/Singapore. This is a late practice submission, so it does not change the competition's closed official leaderboard. The account's [Kaggle submissions page](https://www.kaggle.com/competitions/widsdatathon2022/submissions) shows the result. The exact visible detail text is preserved in [kaggle_submission_receipt.txt](kaggle_submission_receipt.txt).

## Submitted model and file

- File: wids_history_residual_submission.csv (generated locally).
- SHA256: 81d29734bec90a0041d74094ef040657457412ae11d23b27e32ef5cf8e5506d2.
- 9,705 unique test IDs, in sample-solution order; exactly id and site_eui columns.
- 9,067 rows use earlier building-group EUI plus a MATLAB LSBoost residual prediction; 638 rows use the 50/50 LSBoost/random-forest fallback.
- Full-data preprocessing uses all 75,757 labeled rows. Residual regression uses 49,384 fitting rows with strictly earlier history. Both fallback models use all labeled rows.
- All three models were refitted in MATLAB with seed 42. No prediction clipping, calibration, or test labels were used.
- Predictions range from 1.1900 to 905.2368, with no missing, infinite, or negative predictions. CSV readback preserved every prediction exactly.

The local model-selection RMSE was 34.93465 on historical years 4 and 5. Kaggle evaluates different test rows; these numbers should not be interpreted as a measured improvement between two models on the same dataset.

The full-data models, fitted preprocessing, component predictions, and data/code provenance are saved under checkpoints. KAGGLE_RESULT.json stores the submission result in machine-readable form.

Kaggle accepted the MATLAB submission (generated locally)
