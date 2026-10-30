%% Evaluate each alternative addition using years 1-4 -> year 5
% Do not reuse the years 1-5 cleaning outputs from the previous comparison.
% This experiment excludes year 6 and does not use Kaggle test data.
widsAblationFolder = fileparts(mfilename('fullpath'));
widsAblationRaw = readtable( ...
    wids_data_file("train.csv"));
widsAblationFitMask = widsAblationRaw.Year_Factor <= 4;
widsAblationValidationMask = widsAblationRaw.Year_Factor == 5;
[widsAblationCleanFit, widsAblationCleanValidation, widsAblationCleaning] = ...
    wids_clean_split(widsAblationRaw(widsAblationFitMask,:), ...
    widsAblationRaw(widsAblationValidationMask,:));
widsAblationEmptyTest = removevars(widsAblationCleanValidation([],:), 'site_eui');
[widsAblationFeatureFit, widsAblationFeatureValidation, ~, widsAblationFeatureParameters] = ...
    wids_alternative_features(widsAblationCleanFit, ...
    widsAblationCleanValidation, widsAblationEmptyTest);
widsAblationFitX = removevars(widsAblationFeatureFit, 'site_eui');
widsAblationValidationX = removevars(widsAblationFeatureValidation, 'site_eui');
widsAblationFitY = widsAblationCleanFit.site_eui;
widsAblationValidationY = widsAblationCleanValidation.site_eui;
widsAblationAddedNames = widsAblationFeatureParameters.AddedPredictors(:);
widsAblationLabels = ["Cleaned baseline"; "All six additions"; ...
    "Without " + widsAblationAddedNames];

%% Check rows, inputs, and response before expensive training
assert(height(widsAblationFitX) == nnz(widsAblationFitMask));
assert(height(widsAblationValidationX) == nnz(widsAblationValidationMask));
assert(~any(widsAblationFitMask & widsAblationValidationMask));
assert(~ismember('Year_Factor', widsAblationFitX.Properties.VariableNames));
assert(~any(ismissing(widsAblationFitX), 'all'));
assert(~any(ismissing(widsAblationValidationX), 'all'));
assert(all(isfinite(widsAblationFitY)) && all(isfinite(widsAblationValidationY)));
fprintf('Fitting rows: %d (years 1-4); validation rows: %d (year 5).\n', ...
    numel(widsAblationFitY), numel(widsAblationValidationY));
fprintf('Imputation medians fitted on years 1-4: year %.0f; Energy Star %.0f.\n', ...
    widsAblationCleaning.Medians.year_built, ...
    widsAblationCleaning.Medians.energy_star_rating);

%% Fixed settings match the previous feature-bundle comparison
widsAblationSettings = struct('Method','LSBoost','NumLearningCycles',200, ...
    'LearnRate',0.05,'MaxNumSplits',31,'MinLeafSize',20,'Seed',42);
widsAblationTree = templateTree(MaxNumSplits=31, MinLeafSize=20, ...
    NumVariablesToSample='all', Reproducible=true);
widsAblationCount = numel(widsAblationLabels);
widsAblationModels = cell(widsAblationCount,1);
widsAblationPredictions = zeros(numel(widsAblationValidationY),widsAblationCount);
widsAblationRMSE = NaN(widsAblationCount,1);
widsAblationMAE = NaN(widsAblationCount,1);
widsAblationSeconds = NaN(widsAblationCount,1);
widsAblationPredictorCounts = zeros(widsAblationCount,1);
for widsAblationIndex = 1:widsAblationCount
    if widsAblationIndex == 1
        widsAblationSelectedNames = setdiff( ...
            widsAblationFitX.Properties.VariableNames, ...
            cellstr(widsAblationAddedNames), 'stable');
    elseif widsAblationIndex == 2
        widsAblationSelectedNames = widsAblationFitX.Properties.VariableNames;
    else
        widsAblationRemoved = widsAblationAddedNames(widsAblationIndex-2);
        widsAblationSelectedNames = setdiff( ...
            widsAblationFitX.Properties.VariableNames, ...
            cellstr(widsAblationRemoved), 'stable');
    end
    widsAblationPredictorCounts(widsAblationIndex) = numel(widsAblationSelectedNames);
    rng(widsAblationSettings.Seed,'twister');
    widsAblationTimer = tic;
    widsAblationModel = fitrensemble( ...
        widsAblationFitX(:,widsAblationSelectedNames), widsAblationFitY, ...
        Method=widsAblationSettings.Method, ...
        NumLearningCycles=widsAblationSettings.NumLearningCycles, ...
        LearnRate=widsAblationSettings.LearnRate, Learners=widsAblationTree);
    widsAblationSeconds(widsAblationIndex) = toc(widsAblationTimer);
    widsAblationModels{widsAblationIndex} = compact(widsAblationModel);
    widsAblationPredicted = predict(widsAblationModel, ...
        widsAblationValidationX(:,widsAblationSelectedNames));
    assert(all(isfinite(widsAblationPredicted)));
    widsAblationPredictions(:,widsAblationIndex) = widsAblationPredicted;
    widsAblationErrors = widsAblationPredicted - widsAblationValidationY;
    widsAblationRMSE(widsAblationIndex) = sqrt(mean(widsAblationErrors.^2));
    widsAblationMAE(widsAblationIndex) = mean(abs(widsAblationErrors));
    fprintf('%d/%d %s: RMSE %.5f, MAE %.5f, training %.1fs.\n', ...
        widsAblationIndex,widsAblationCount,widsAblationLabels(widsAblationIndex), ...
        widsAblationRMSE(widsAblationIndex), widsAblationMAE(widsAblationIndex), ...
        widsAblationSeconds(widsAblationIndex));
    % Save completed rows so progress is inspectable while MATLAB is busy.
    widsAblationCompleted = (1:widsAblationIndex)';
    widsAblationProgress = table(widsAblationLabels(widsAblationCompleted), ...
        widsAblationPredictorCounts(widsAblationCompleted), ...
        widsAblationRMSE(widsAblationCompleted), widsAblationMAE(widsAblationCompleted), ...
        widsAblationSeconds(widsAblationCompleted), ...
        'VariableNames',{'Experiment','Predictors','ValidationRMSE','ValidationMAE','TrainingSeconds'});
    writetable(widsAblationProgress,fullfile(widsAblationFolder,'wids_ablation_progress.csv'));
end

%% Positive delta means removal is harmful; negative means removal helps
widsAblationResults = widsAblationProgress;
widsAblationResults.RMSEChangeFromFull = widsAblationRMSE-widsAblationRMSE(2);
widsAblationResults.RMSEChangePercent = ...
    100*widsAblationResults.RMSEChangeFromFull/widsAblationRMSE(2);
disp(widsAblationResults);
writetable(widsAblationResults,fullfile(widsAblationFolder,'wids_ablation_results.csv'));
fprintf('Single-drop effects apply within this bundle and fixed model configuration.\n');
fprintf('Several individually removable features must be tested together before dropping them all.\n');
clear widsAblationModel;
