# Configuration and result contract

## Fixed CPU budget

The manifest fixes a bounded first comparison. It does not use automatic hyperparameter optimization, random cross-validation, the Kaggle test set, or year-6 targets. A common seed per fold is used across configurations: 1042 for fold 1 and 2042 for fold 2. Each configuration is evaluated once per fold; the ranking does not quantify seed uncertainty.

| Stage/family | Configurations | Jobs | Main settings |
|---|---:|---:|---|
| CPU pilot | 4 | 8 | Ridge reference; 100-tree forest; 256-dimensional kernel; 32-unit net |
| Bagged/forest trees | 6 | 12 | 300â€“500 trees, leaves 10â€“50, 511â€“2047 split caps, mtry 8/20/40/all |
| Approximate Gaussian kernel | 6 | 12 | 1024/2048 expansion dimensions, auto or 5/10/20 scale, bounded L2 penalties |
| Neural regression | 6 | 12 | 32/64/128 units or [64,32], L2 0.001/0.01/0.1, 500 iterations |
| Ridge linear reference | 3 | 6 | L2 0.0001/0.01/1, 500 LBFGS iterations |

The exact settings are authoritative in `manifests/configurations.json`. A name such as `l1e3` means lambda **1e-3**. The CPU pilot net/kernel/linear fits have a 100-iteration limit. Pilot scores stay in a separate leaderboard. The forest family includes five random-predictor configurations and one all-predictor bagging reference. `Mtry` refers to the 59 source table columns.

The kernels use `fitrkernel` with a least-squares learner and a 1024 MB **transformed-data block allowance**, not a total process memory cap. Feature expansion avoids an unrestricted exact-kernel search. No full Gaussian-process model or unrestricted kernel SVM search is included. `fitrnet` uses its standard fully connected architecture, ReLU activations, and the supplied L2/iteration settings. Basic `fitrnet` needs Statistics and Machine Learning Toolbox; this package does not use a custom `dlnetwork`. [Kernel documentation](https://www.mathworks.com/help/stats/fitrkernel.html), [neural regression documentation](https://www.mathworks.com/help/stats/fitrnet.html).

## Preprocessing and leakage controls

The original `wids_clean_split.m` is copied without changes. Zero construction years become missing; positive historic years remain. Construction-year and Energy Star missingness flags are kept, and those two numeric variables are imputed from fitting medians. The dropped weather variables stay out. Missing/unseen categories use the cleaner's reserved `__unknown__` value. Unexpected nonfinite values in the other selected numeric predictors cause a clear failure instead of silently dropping rows or changing the cleaning specification.

For the linear/kernel/net representation, numeric variables and numeric 0/1 missingness flags are centered and scaled using fitting statistics. A constant fitting column uses a scale of 1. Categorical dummies stay 0/1. The validation vocabulary cannot introduce a dummy column. For the forest representation, categories stay categorical and missingness flags are explicitly numeric. A synthetic probe includes an unobserved reserved tree category and requires finite predictions on the installed release.

The fitting targets are always supplied in their original units. No outer-fold validation data is passed to training for early stopping or feature selection. Iteration limits are fixed in advance. `fitrnet` can return a model without convergence, so inspect `DiagnosticsText`, `result.mat` diagnostics, and `matlab.log` before interpreting the winner. Kernel/linear optimizer diagnostics are saved too. A completed job means fitting and prediction finished with finite output; it does not certify optimizer convergence. [MathWorks convergence guidance](https://www.mathworks.com/help/stats/fitrnet.html).

## CPU pilot resources and scaling

The example profile contains a **provisional sizing estimate** of one node, 4 CPU cores, 32 GB, and 1 hour. These numbers are not a statement of your allocation, a queue guarantee, or measured runtimes. Confirm them against the actual CPU queue. One MATLAB process runs per job with no parallel pool. The scheduler core count bounds the MATLAB and BLAS thread limits; additional cores may not speed up the serial tree trainer. Start with a single pilot job, then keep at most two active jobs until license availability and memory/runtime use are understood.

The probe is an additional PBS job, separate from the 50 model jobs. It performs tiny synthetic fits plus real-data preprocessing checks only. The eight pilot jobs use the complete frozen folds. Review their walltime and maximum resident set size in `results/<tag>/scheduler/*.time.txt` and the actual PBS usage from `qstat -fx <job-id>` when available. Adjust CPU memory/walltime before rendering comparison jobs. Keep the thread count fixed within a run tag. A new thread count or MATLAB/toolbox version requires a new run tag and probe, so scores from different environments are not silently pooled.

At the illustrative profile ceiling, eight one-hour pilot jobs request up to 32 CPU core-hours, plus the probe; actual runtime is unknown. The 42 comparison jobs would request up to 168 CPU core-hours at that ceiling. This is a resource-time envelope, not an NSCC billing quote. Avoid submitting all jobs together before inspecting pilot usage. Failed jobs may also consume allocation.

Prepared matrices, saved models, and result files can occupy several GB across the full run. Keep checkpoints and logs in a confirmed shared directory with adequate quota, and download them. No temporary node-local directory is used for durable checkpoints. NSCC documents scratch expiry and automatic cleanup of node-local storage; check your actual filesystem policies. [NSCC storage description](https://nsccsg.github.io/systems/aspire2a/system-specifications/).

## GPU follow-up

No GPU resource settings or GPU jobs are generated. Revisit GPU use after the CPU probe and pilots establish the full MATLAB release, successful licenses, measured bottlenecks, and the actual GPU allocation/queue. Current MathWorks documentation adds `fitrnet` GPU-array training in R2024b and `fitrkernel` in R2025a, requiring Parallel Computing Toolbox. GPU `fitrensemble` does not support `Method='Bag'`, so the forest comparison stays on CPU. Eligibility is not evidence of a speedup. A later GPU comparison needs separate reproducibility and CPU/GPU agreement checks. [Neural GPU support](https://www.mathworks.com/help/stats/fitrnet.html), [kernel GPU support](https://www.mathworks.com/help/stats/fitrkernel.html), [ensemble GPU limitations](https://www.mathworks.com/help/stats/fitrensemble.html).

## Checkpoints and per-job outputs

Each job writes only to `results/<run_tag>/jobs/job_NNNN/`:

| File | Contents |
|---|---|
| `prepared.mat` | Fitting/validation matrices or tables, IDs, unchanged targets, medians/vocabularies/scaling, identity |
| `model.mat` | Fitted model, optimizer diagnostics, fit duration, post-fit RNG state, identity |
| `state.json` | Last persisted phase: prepared, training, predicting, complete |
| `predictions.csv` | Exactly `id,site_eui,prediction`, in the frozen validation-row order |
| `result.mat` | Predictions, preprocessing schema, metrics, optimizer diagnostics, identity |
| `result.json` | Atomic completion marker, SSE/SAE/N, RMSE/MAE, timing, diagnostics text, prediction checksum |
| `failure.json` | Most recent caught error, if any; a later success can leave this historical file present |
| `matlab.log` | MATLAB diary |
| `running.lock/` | Atomic job lock while the runner is active |

MAT and JSON checkpoints are written to temporary files and renamed on the same filesystem. A successful matching result is preserved on resubmission. After interruption, the runner reuses a matching prepared checkpoint and, if present, fitted-model checkpoint. **There is no mid-fit optimizer or partial-tree resume.** If killed during fitting, that single configuration/fold fit restarts from its fixed seed. Other finished jobs remain reusable. A hard scheduler kill may leave a lock and a temporary file.

For a stale lock: confirm the specific job is absent/finished in `qstat`, inspect `qstat -fx <job-id>` and the logs, then remove only that job's empty `running.lock` directory with `rmdir`. Do not remove a lock for a live job. Re-render and resubmit that job's same PBS file. Change code, data, manifests, MATLAB version, or thread count only in a separately versioned run/package; do not overwrite finished comparisons.

## Aggregation

`python3 nscc.py aggregate --run-tag <tag>` runs without MATLAB. It verifies the frozen package, matching successful probe, job/configuration identity, prediction checksum, exact ID/order, target values, finite predictions, expected row counts, and recomputed SSE/SAE/RMSE/MAE. A configuration enters a leaderboard only with both valid folds. Missing/failed/invalid jobs never receive a partial-fold score. Invalid output is excluded and the command exits 2; missing jobs are listed without an error while a run is in progress.

Outputs are `job_status.csv`, `all_configurations.csv`, `pilot_leaderboard.csv`, `leaderboard.csv`, and `aggregation_status.json`. The comparison leaderboard uses only `Stage='compare'`, sorted by pooled RMSE, then supporting pooled MAE, then configuration ID for a deterministic tie. The whole run remains provisional until `ComparisonComplete` is true. Aggregation does not infer statistical significance or select on year 6.

The previous local cleaned-baseline pooled scores were RMSE 42.69539 and MAE 24.56340 in the supplied report. They are historical context, not newly measured NSCC results. Integrate the local boosted-tree tuning results only when the source predictors, folds, row identities, and metric definitions match.
