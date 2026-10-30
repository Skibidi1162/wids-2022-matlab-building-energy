# Local tuning completed

The current best local configuration is **L07: 300 boosted trees, learning rate 0.05, maximum 31 splits, minimum leaf size 5**. The 59 baseline predictors are unchanged.

| Metric | Reference L01 | Selected L07 |
|---|---:|---:|
| Year-4 RMSE | 43.14590 | 41.43553 |
| Year-5 RMSE | 42.37393 | 42.08551 |
| Pooled RMSE | 42.69539 | **41.81750** |
| Pooled MAE | 24.56340 | **24.20705** |

Pooled RMSE improved by **2.06%**. This is selection performance on the historical tuning splits, not a new independent test score. Year 6 was not rescored during this search.

## Full ranking

| ID | Trees | Learn rate | Max splits | Min leaf | Pooled RMSE | Pooled MAE |
|---|---:|---:|---:|---:|---:|---:|
| L07 | 300 | 0.05 | 31 | 5 | 41.81750 | 24.20705 |
| L06 | 300 | 0.05 | 63 | 20 | 42.18283 | 24.71391 |
| L02 | 400 | 0.05 | 31 | 20 | 42.45934 | 24.85984 |
| L04 | 400 | 0.025 | 31 | 20 | 42.59012 | 24.21002 |
| L08 | 300 | 0.05 | 31 | 50 | 42.59632 | 24.28131 |
| L01 | 200 | 0.05 | 31 | 20 | 42.69539 | 24.56340 |
| L05 | 300 | 0.05 | 15 | 20 | 42.81358 | 24.51387 |
| L03 | 400 | 0.10 | 31 | 20 | 44.73170 | 26.79725 |

## Validation and reproducibility

- All 16 configuration/fold fits completed with finite targets, predictions, and aggregate error metrics.
- Preprocessing was learned separately on years 1â€“3 for validation year 4 and years 1â€“4 for validation year 5.
- Aggregation uses total squared error divided by total validation rows (31,254), followed by the square root.
- The reference score matched the earlier benchmark exactly; resuming reused its checkpoints without retraining.
- Incomplete configurations are excluded. A deliberately invalid-target fixture confirmed failed runs publish an empty leaderboard rather than retain stale scores, and error records round-trip through CSV.
- Data SHA-256: `f6c0e3fceaddd70e2d291962b9f2aad871081f99dcb761b61bd06e976333da46`.
- Models, predictions, fitting-only preparation parameters, and signatures are saved in the fold checkpoints.

The MATLAB connector stopped waiting after its 300-second limit, but the running search continued to write checkpoints. All remaining fits finished successfully; the final CSV and checkpoints were verified afterward.

## Work split

This chat owns local LSBoost tuning. **WiDS NSCC model benchmarks** owns the separate upload package, environment/toolbox probes, and alternative-model jobs. The NSCC package has four CPU pilots and 21 benchmark configurations across bagged trees, approximate kernel regression, neural networks, and a regularized linear reference. Remote execution is pending the user's real NSCC environment and allocation details.

Next, compare completed NSCC pooled scores against local L07 under the same protocol, then confirm the chosen model on year 6 and prepare the final training/prediction run.
