%% Reproduce cleaning, then add the project features
% Run this script from any folder. Companion functions must be beside it.
widsScriptFolder = fileparts(mfilename('fullpath'));
run(fullfile(widsScriptFolder, 'prepare_wids_data.m'));

%% Retain rare historical construction years for review
% These are building-year records, not necessarily distinct buildings.
widsHistoricTrainingRecords = widsTrainRaw( ...
    widsTrainRaw.year_built > 0 & widsTrainRaw.year_built < 1800, ...
    {'id', 'Year_Factor', 'facility_type', 'year_built', 'floor_area'});
widsHistoricTestRecords = widsTestRaw( ...
    widsTestRaw.year_built > 0 & widsTestRaw.year_built < 1800, ...
    {'id', 'Year_Factor', 'facility_type', 'year_built', 'floor_area'});

%% Build predictors using the existing years 1-5 / year 6 partition
% alpha=20 is an initial smoothing choice, not a tuned optimum.
widsFacilitySmoothing = 20;
[widsModelTrain, widsModelValidation, widsTestFeatures, widsFeatureParameters] = ...
    wids_engineer_features(widsModelTrain, widsModelValidation, ...
    widsTestClean, widsFacilitySmoothing);
widsPredictorNames = widsFeatureParameters.PredictorNames;
widsTrainingData = widsModelTrain(:, widsPredictorNames);
widsValidationData = widsModelValidation(:, widsPredictorNames);
widsTrainingOutput = widsModelTrain.site_eui;
widsValidationOutput = widsModelValidation.site_eui;

%% Summary
fprintf('\nAfter feature engineering: %d predictors.\n', numel(widsPredictorNames));
fprintf('Year_Factor is retained in raw data for partitioning, excluded from predictors.\n');
fprintf('Historic records retained: labeled %d; Kaggle test %d.\n', ...
    height(widsHistoricTrainingRecords), height(widsHistoricTestRecords));
fprintf('Facility means: log(site_eui), smoothing %.0f, leave-one-year-out training values.\n', ...
    widsFacilitySmoothing);
fprintf('Validation and Kaggle encodings use training years 1-5 only.\n');
fprintf('Response remains site_eui; no model has been trained.\n');
