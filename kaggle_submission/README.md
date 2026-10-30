# MATLAB Kaggle submission

This folder refits the selected HISTORY_RESIDUAL method on all 75,757 labeled WiDS Datathon 2022 rows and predicts the 9,705 competition test rows. All model fitting and prediction use MATLAB with Statistics and Machine Learning Toolbox.

Run one stage at a time from this folder:

```matlab
run_wids_submission("prepare");
run_wids_submission("residual");
run_wids_submission("boost");
run_wids_submission("forest");
run_wids_submission("export");
```

The residual LSBoost uses 49,384 fitting rows with strictly earlier building-group history, 73 predictors, 300 trees, learning rate 0.05, maximum 31 splits, minimum leaf size 5, and seed 42. For the 9,067 matched test rows, prediction is latest earlier EUI plus predicted change. The remaining 638 rows use a 50/50 blend of boosted regression and random forest, both refitted on all labeled rows using 59 baseline predictors. Duplicate earlier building-year readings are averaged. No clipping or calibration is applied.

Input paths are in wids_submission_identity.m. Preprocessing is fitted on labeled training data only; history for a row uses only earlier fitting years. The copied cleaning/history helpers and predictor list match the completed local benchmark. There are no test targets available for local scoring.

The exported file is **wids_history_residual_submission.csv**, containing exactly id and site_eui in sample_solution.csv ID order. Export checks model/source/data identity, row counts, unique IDs, finite predictions, full prediction precision, exact CSV readback, and SHA256. Checkpoints retain models, fitted preprocessing, history metadata, predictions, and provenance.

These are full-data refits of the method selected using historical validation years 4 and 5 (pooled RMSE 34.93465). Kaggle scoring is a separate evaluation. See SUBMISSION_RESULT.md and KAGGLE_RESULT.json after an actual submission for the receipt and any returned scores.
