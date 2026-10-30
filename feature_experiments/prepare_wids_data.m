%% Import WiDS data and prepare a reproducible baseline
% Run this script before opening a new Regression Learner session.
% Raw CSV files are read only. No normalization is applied here.
widsProjectFolder = fileparts(mfilename('fullpath'));
widsDataFolder = wids_data_dir();
widsTrainRaw = readtable(fullfile(widsDataFolder, 'train.csv'));
widsTestRaw = readtable(fullfile(widsDataFolder, 'test.csv'));

%% Reserve the latest labeled year for validation
% Kaggle test.csv contains year 7. Year 6 provides a forward-year check.
widsValidationYear = max(widsTrainRaw.Year_Factor);
widsValidationMask = widsTrainRaw.Year_Factor == widsValidationYear;
widsFitMask = widsTrainRaw.Year_Factor < widsValidationYear;
widsTrainId = widsTrainRaw.id;
widsTestId = widsTestRaw.id;

%% Remove identifiers and four sparse weather predictors
% These weather columns are missing in 54-60% of the labeled rows and
% 88-94% of Kaggle test rows. Dropping them is a baseline modeling choice.
widsCleaningParameters = struct;
widsCleaningParameters.ValidationYear = widsValidationYear;
widsCleaningParameters.DroppedPredictors = ...
    ["direction_max_wind_speed", "direction_peak_wind_speed", ...
     "max_wind_speed", "days_with_fog"];
widsRemoveNames = ["id", widsCleaningParameters.DroppedPredictors];
widsTrainClean = removevars(widsTrainRaw, widsRemoveNames);
widsTestClean = removevars(widsTestRaw, widsRemoveNames);

%% Mark construction year zero as unknown
% Positive years before 1800 are retained: age alone does not prove an error.
widsTrainClean.year_built(widsTrainClean.year_built == 0) = NaN;
widsTestClean.year_built(widsTestClean.year_built == 0) = NaN;

%% Preserve building categories using a shared vocabulary
% Learn levels from the fitting rows. Reserve a level for future unknowns.
widsCategoryNames = ["State_Factor", "building_class", "facility_type"];
widsUnknownLevel = "__unknown__";
for widsCategoryName = widsCategoryNames
    widsTrainText = strtrim(string(widsTrainClean.(widsCategoryName)));
    widsTestText = strtrim(string(widsTestClean.(widsCategoryName)));
    widsFitText = widsTrainText(widsFitMask);
    widsLevels = unique(widsFitText(~ismissing(widsFitText) & widsFitText ~= ""));
    widsLevels = unique([widsLevels; widsUnknownLevel], 'stable');
    widsTrainText(~ismember(widsTrainText, widsLevels)) = widsUnknownLevel;
    widsTestText(~ismember(widsTestText, widsLevels)) = widsUnknownLevel;
    widsTrainClean.(widsCategoryName) = categorical(widsTrainText, widsLevels);
    widsTestClean.(widsCategoryName) = categorical(widsTestText, widsLevels);
    widsCleaningParameters.CategoryLevels.(widsCategoryName) = widsLevels;
end

%% Fill missing values using only years 1-5
% The same medians are applied to validation rows and Kaggle test rows.
% Flags allow a model to distinguish an imputed value from a recorded value.
widsImputeNames = ["year_built", "energy_star_rating"];
for widsImputeName = widsImputeNames
    widsTrainMissing = ismissing(widsTrainClean.(widsImputeName));
    widsTestMissing = ismissing(widsTestClean.(widsImputeName));
    widsMissingFlag = widsImputeName + "_missing";
    widsTrainClean.(widsMissingFlag) = widsTrainMissing;
    widsTestClean.(widsMissingFlag) = widsTestMissing;
    widsMedian = median(widsTrainClean.(widsImputeName)(widsFitMask), 'omitmissing');
    widsTrainClean.(widsImputeName)(widsTrainMissing) = widsMedian;
    widsTestClean.(widsImputeName)(widsTestMissing) = widsMedian;
    widsCleaningParameters.Medians.(widsImputeName) = widsMedian;
end

%% Create matching model tables and separate responses
widsPredictorNames = widsTrainClean.Properties.VariableNames;
widsPredictorNames(strcmp(widsPredictorNames, 'site_eui')) = [];
widsTestClean = widsTestClean(:, widsPredictorNames);
widsModelTrain = widsTrainClean(widsFitMask, :);
widsModelValidation = widsTrainClean(widsValidationMask, :);
widsTrainingData = widsModelTrain(:, widsPredictorNames);
widsTrainingOutput = widsModelTrain.site_eui;
widsValidationData = widsModelValidation(:, widsPredictorNames);
widsValidationOutput = widsModelValidation.site_eui;

%% Summarize cleaning and verify the model inputs
widsMissingBeforeTrain = sum(ismissing(widsTrainRaw), 1);
widsMissingBeforeTest = sum(ismissing(widsTestRaw), 1);
widsCleaningSummary = table( ...
    ["train.csv"; "test.csv"], ...
    [height(widsTrainClean); height(widsTestClean)], ...
    [sum(widsMissingBeforeTrain); sum(widsMissingBeforeTest)], ...
    [sum(ismissing(widsTrainClean), 'all'); sum(ismissing(widsTestClean), 'all')], ...
    'VariableNames', {'Source', 'RowsRetained', 'OriginalMissingEntries', 'RemainingMissingEntries'});
disp(widsCleaningSummary);
fprintf('Predictors: %d, including 3 categorical columns and 2 missing-value flags.\n', numel(widsPredictorNames));
fprintf('Training years 1-5: %d rows; validation year %.0f: %d rows.\n', ...
    height(widsModelTrain), widsValidationYear, height(widsModelValidation));
fprintf('Training-only imputation medians: construction year %.1f; Energy Star %.1f.\n', ...
    widsCleaningParameters.Medians.year_built, widsCleaningParameters.Medians.energy_star_rating);
fprintf('Invalid construction years marked unknown: train %d; test %d.\n', ...
    nnz(widsTrainRaw.year_built == 0), nnz(widsTestRaw.year_built == 0));
fprintf('Data is ready for inspection; no model has been trained.\n');
