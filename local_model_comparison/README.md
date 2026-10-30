# Local model comparison

Measured results are in [RESULTS.md](RESULTS.md); competition research is in [TOP_SOLUTIONS.md](TOP_SOLUTIONS.md).

## Protocol

Predict site_eui in original units using the same two forward folds: years 1â€“3 fit/year 4 validation (22,054/12,946 rows), and years 1â€“4 fit/year 5 validation (35,000/18,308 rows). Pooled RMSE is sqrt(total squared error / total validation rows). These folds are model-selection data. Year 6 was examined during earlier feature experiments, so it is not an untouched final test. Competition test labels are unavailable locally.

The L07 boosted reference uses 300 trees, learning rate 0.05, maximum 31 splits, minimum leaf size 5, and 59 frozen predictors. Each split fits its own cleaning and imputation. Trees use categorical tables. Other families use training-fitted numeric scaling and one-hot categories (119/124 encoded columns). Target, ID, and Year_Factor are excluded from the baseline predictors.

## Experiments and execution

Run from this folder using MATLAB R2026b and Statistics and Machine Learning Toolbox. The source data path is in wids_model_signature.m. Preserve the sibling local_tuning folder and its archived results/provenance for the boosted reference.

    run_model_comparison
    run_longer_network_case(4);
    run_longer_network_case(5);
    verify_model_comparison;
    evaluate_wids_blends;
    check_building_history_logic;
    run_building_history_case(4);
    run_building_history_case(5);
    summarize_history_results;

The first command compares random forest, bagged trees, neural network, approximate Gaussian kernel, and ridge regression. The separate longer-network runner preserves the original experiment signatures. The blend evaluator compares forest weights 0.25, 0.50, and 0.75 with the existing boosted model.

The history experiment reconstructs building groups from raw stable attributes, averages duplicate building-year readings, and uses fitting labels from strictly earlier years. It tests a latest-reading baseline, direct boosted regression with history, and residual boosting with a no-history ensemble fallback. The logic fixture checks duplicate averaging, temporal gaps, and invariance to query/current/future targets. History and no-history groups are scored separately.

## Saved evidence

Checkpoints contain model configuration, data/code provenance, predictions, row IDs, fitted preprocessing, available models, and solver diagnostics. Seed 42 and local CPU execution are fixed. Only matching successful checkpoints are reused. Changing fingerprinted sources invalidates matching checkpoints; preserve completed-run provenance.

The verification functions recompute metrics against raw labels and check saved SSE/SAE, row alignment, and provenance. CSV summaries and solver_diagnostics.txt are in results. Runtime columns cover fitting only. Iteration limits do not establish convergence, and a compact screen cannot rule out a model family. Implementation stays in MATLAB on both local and NSCC tracks. The winners' external libraries guide methods and feature choices; broader searches will use confirmed MATLAB toolboxes and resources.
