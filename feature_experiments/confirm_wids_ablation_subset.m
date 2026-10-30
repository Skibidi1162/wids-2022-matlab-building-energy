%% Verify the reduced feature bundle suggested by the single-drop results
% Run ablate_wids_features first. This step uses only its years 1-4 -> 5 data.
assert(exist('widsAblationResults','var') == 1, 'Run ablate_wids_features first.');
widsSubsetFolder = fileparts(mfilename('fullpath'));
% Keep additions whose removal raised validation RMSE, with a numerical
% tolerance only. This is a provisional, validation-selected candidate.
widsSubsetKeepMask = widsAblationRMSE(3:end) > widsAblationRMSE(2) + 1e-10;
widsSubsetAddedNames = widsAblationAddedNames(widsSubsetKeepMask);
widsSubsetBaselineNames = setdiff(widsAblationFitX.Properties.VariableNames, ...
    cellstr(widsAblationAddedNames),'stable');
widsSubsetPredictorNames = [widsSubsetBaselineNames, cellstr(widsSubsetAddedNames)'];
rng(widsAblationSettings.Seed,'twister');
widsSubsetTimer = tic;
widsSubsetModel = fitrensemble(widsAblationFitX(:,widsSubsetPredictorNames), ...
    widsAblationFitY, Method=widsAblationSettings.Method, ...
    NumLearningCycles=widsAblationSettings.NumLearningCycles, ...
    LearnRate=widsAblationSettings.LearnRate, Learners=widsAblationTree);
widsSubsetSeconds = toc(widsSubsetTimer);
widsSubsetPredicted = predict(widsSubsetModel, ...
    widsAblationValidationX(:,widsSubsetPredictorNames));
assert(all(isfinite(widsSubsetPredicted)));
widsSubsetErrors = widsSubsetPredicted - widsAblationValidationY;
widsSubsetRMSE = sqrt(mean(widsSubsetErrors.^2));
widsSubsetMAE = mean(abs(widsSubsetErrors));
widsSubsetResult = table("Reduced additions verified together", ...
    numel(widsSubsetPredictorNames), widsSubsetRMSE, widsSubsetMAE, ...
    widsSubsetSeconds, widsSubsetRMSE-widsAblationRMSE(2), ...
    100*(widsSubsetRMSE-widsAblationRMSE(2))/widsAblationRMSE(2), ...
    'VariableNames',widsAblationResults.Properties.VariableNames);
widsAblationConfirmedResults = [widsAblationResults;widsSubsetResult];
disp(widsAblationConfirmedResults);
fprintf('Reduced bundle retains: %s.\n',strjoin(widsSubsetAddedNames,', '));
writetable(widsAblationConfirmedResults, ...
    fullfile(widsSubsetFolder,'wids_ablation_confirmed_results.csv'));

%% Score familiar versus unfamiliar facility/state pairs without more fits
widsUnknownPairRows = string(widsAblationFeatureValidation.facility_state) == "__unknown__";
widsSubgroupLabels = ["Known facility-state pairs";"Unseen facility-state pairs"];
widsSubgroupModelLabels = ["Cleaned baseline";"All six additions";"Without facility_state";"Reduced additions"];
widsSubgroupPredictions = [widsAblationPredictions(:,[1,2,4]),widsSubsetPredicted];
widsAblationSubgroups = table;
for widsGroupIndex = 1:2
    if widsGroupIndex == 1
        widsGroupMask = ~widsUnknownPairRows;
    else
        widsGroupMask = widsUnknownPairRows;
    end
    for widsGroupModelIndex = 1:4
        widsGroupErrors = widsSubgroupPredictions(widsGroupMask,widsGroupModelIndex) ...
            - widsAblationValidationY(widsGroupMask);
        widsGroupResult = table(widsSubgroupLabels(widsGroupIndex), ...
            widsSubgroupModelLabels(widsGroupModelIndex),nnz(widsGroupMask), ...
            sqrt(mean(widsGroupErrors.^2)),mean(abs(widsGroupErrors)), ...
            'VariableNames',{'Subgroup','Model','Rows','RMSE','MAE'});
        widsAblationSubgroups = [widsAblationSubgroups;widsGroupResult]; %#ok<AGROW>
    end
end
disp(widsAblationSubgroups);
writetable(widsAblationSubgroups,fullfile(widsSubsetFolder,'wids_ablation_subgroups.csv'));
fprintf('Year 6 and Kaggle targets were not used for these experiments.\n');
