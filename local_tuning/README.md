# Local boosted-tree tuning

This track tunes the current MATLAB LSBoost regressor using the frozen 59-predictor baseline. The NSCC model-family benchmark is being prepared separately in the **WiDS NSCC model benchmarks** chat.

## Run or resume

From this folder in MATLAB:

```matlab
results = run_local_tuning();
```

To run only the reference configuration:

```matlab
reference = run_local_tuning("","","L01");
```

The local runner targets the Windows MATLAB installation and defaults to `<your-data-directory>\train.csv`. You can supply an alternate data-file path and result directory as the first two arguments. Optional configuration IDs are the third argument.

## Fixed evaluation protocol

- Years 1â€“3 â†’ year 4: 22,054 fitting rows and 12,946 validation rows.
- Years 1â€“4 â†’ year 5: 35,000 fitting rows and 18,308 validation rows.
- Refit imputation and categorical vocabularies inside each fitting split.
- Keep `Year_Factor`, `id`, and the response outside the predictor columns.
- Keep the response on the original `site_eui` scale and use seed 42.
- Rank complete two-fold configurations by pooled RMSE `sqrt(sum(SSE)/sum(N))`, then pooled MAE. A configuration with an unsuccessful or missing fold is excluded from ranking.
- Year 6 is reserved for later confirmation; it was already inspected earlier and is not an independent untouched final test.
- Numeric features remain unscaled for these tree models. Other model families in the NSCC track will standardize applicable predictors using fitting-only statistics.

## Search configurations

| ID | Description | Trees | Learn rate | Maximum splits | Minimum leaf size |
|---|---|---:|---:|---:|---:|
| L01 | Reference | 200 | 0.05 | 31 | 20 |
| L02 | More trees | 400 | 0.05 | 31 | 20 |
| L03 | Faster learning | 400 | 0.10 | 31 | 20 |
| L04 | Slower learning | 400 | 0.025 | 31 | 20 |
| L05 | Shallower trees | 300 | 0.05 | 15 | 20 |
| L06 | Deeper trees | 300 | 0.05 | 63 | 20 |
| L07 | Smaller leaves | 300 | 0.05 | 31 | 5 |
| L08 | Larger leaves | 300 | 0.05 | 31 | 50 |

This is a bounded first search, not an exhaustive optimization. Every row is a distinct configuration; all use the same fitting and validation records.

## Checkpoints and verification

Each completed fold is saved as a compact model plus preprocessing metadata, validation record IDs, predictions, and metrics in `results/Lxx_yearY.mat`. Successful checkpoints are reused only if the dataset SHA-256, selected predictors, MATLAB version, preparation code, runner code, and configuration match.

`results/local_tuning_fold_results.csv` records completed folds and errors. `results/local_tuning_results.csv` ranks configurations with both successful folds. The files update after every fit so progress can be inspected while MATLAB is busy.

Before the full search, the reference reproduced pooled RMSE **42.69538875**, the metric-aggregation test excluded incomplete configurations, and a resume test reused both reference checkpoints without changing them.

No NSCC job is launched from this local runner. Use the separate NSCC chat for its upload package, environment checks, scheduler settings, and submission instructions.

## Completed first search

All eight configurations completed both folds. **L07** led with 300 trees,
learning rate 0.05, maximum 31 splits, and minimum leaf size 5. Its pooled
RMSE is **41.81749901**, compared with **42.69538875** for L01 (a 2.06%
improvement). Its pooled MAE is 24.20705 versus 24.56340 for the reference.
L07 improved RMSE on both year 4 and year 5.

The two L07 checkpoints contain models fitted on years 1â€“3 and years 1â€“4,
respectively. They are validation models, not final all-data deployment fits.
Year-6 confirmation remains deferred until the NSCC model comparison.

The exact source used for this completed search is archived in
`results/provenance`, and `completed_search_identity.mat` records its input
and source signature. After this search, finite-response/error guards and
empty-leaderboard publication were strengthened and tested. The updated
runner deliberately invalidates checkpoints created by a different source
version. Use a fresh result directory for another search; the completed
scores and models remain valid and preserved.
