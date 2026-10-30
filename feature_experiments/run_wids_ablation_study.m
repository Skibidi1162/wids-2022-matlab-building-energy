%% Reproduce the complete feature-ablation study
widsStudyFolder = fileparts(mfilename('fullpath'));
run(fullfile(widsStudyFolder,'ablate_wids_features.m'));
run(fullfile(widsStudyFolder,'confirm_wids_ablation_subset.m'));
run(fullfile(widsStudyFolder,'check_wids_feature_stability.m'));
