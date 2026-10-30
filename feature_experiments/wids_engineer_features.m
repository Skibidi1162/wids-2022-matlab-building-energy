function [trainFeatures, validationFeatures, testFeatures, parameters] = ...
    wids_engineer_features(trainTable, validationTable, testTable, smoothing)
%WIDS_ENGINEER_FEATURES Add size, seasonal weather, and facility features.
% Inputs are already cleaned tables. Only trainTable responses are used to
% construct predictors. Its Year_Factor defines leave-one-year-out encoding
% folds. The outer validation year must remain separate when scoring models.
% For any additional model-validation split, refit this entire preparation
% on that split's fitting rows; do not randomly repartition encoded tables.
arguments
    trainTable table
    validationTable table
    testTable table
    smoothing (1,1) double {mustBeFinite, mustBePositive} = 20
end

trainingYears = trainTable.Year_Factor;
encodingYears = unique(trainingYears);
if numel(encodingYears) < 2
    error('WiDS:InsufficientYears', ...
        'At least two training years are needed for out-of-fold encoding.');
end
if any(~isfinite(trainTable.site_eui) | trainTable.site_eui <= 0)
    error('WiDS:InvalidResponse', 'Training site_eui must be positive and finite.');
end

trainFeatures = addSizeAndWeather(trainTable);
validationFeatures = addSizeAndWeather(validationTable);
testFeatures = addSizeAndWeather(testTable);

%% Encode each training year using only the other training years
% This excludes every row's own target and the other targets in its year.
% Each fold also has its own global mean, excluding the held-out year.
facility = string(trainTable.facility_type);
logResponse = log(trainTable.site_eui);
trainingEncoding = zeros(height(trainTable), 1);
foldEncodings = cell(numel(encodingYears), 1);
for yearIndex = 1:numel(encodingYears)
    heldOut = trainingYears == encodingYears(yearIndex);
    foldEncoding = fitFacilityEncoding(facility(~heldOut), ...
        logResponse(~heldOut), smoothing);
    trainingEncoding(heldOut) = applyFacilityEncoding(facility(heldOut), foldEncoding);
    foldEncodings{yearIndex} = foldEncoding;
end
trainFeatures.facility_log_eui_mean = trainingEncoding;

%% Use all fitting years to encode the outer validation and Kaggle data
fullEncoding = fitFacilityEncoding(facility, logResponse, smoothing);
validationFeatures.facility_log_eui_mean = ...
    applyFacilityEncoding(string(validationTable.facility_type), fullEncoding);
testFeatures.facility_log_eui_mean = ...
    applyFacilityEncoding(string(testTable.facility_type), fullEncoding);

parameters = struct;
parameters.LogBase = 'natural';
parameters.ResponseTransform = 'none; site_eui remains on its original scale';
parameters.EncodingResponse = 'log(site_eui)';
parameters.FacilityEncoding = fullEncoding;
parameters.EncodingFoldYears = encodingYears;
parameters.EncodingFoldMappings = foldEncodings;
parameters.RemovedPredictors = "Year_Factor";
parameters.AddedPredictors = ["log_floor_area", "winter_avg_temp", ...
    "summer_avg_temp", "summer_winter_temp_difference", ...
    "yearly_temperature_range", "total_degree_days", "facility_log_eui_mean"];
parameters.PredictorNames = trainFeatures.Properties.VariableNames;
parameters.PredictorNames(strcmp(parameters.PredictorNames, 'site_eui')) = [];
testFeatures = testFeatures(:, parameters.PredictorNames);
end

function features = addSizeAndWeather(source)
% Monthly temperatures are Fahrenheit. Winter is Dec/Jan/Feb of this record.
if any(~isfinite(source.floor_area) | source.floor_area <= 0)
    error('WiDS:InvalidArea', 'floor_area must be positive and finite before log.');
end
features = removevars(source, 'Year_Factor');
features.log_floor_area = log(source.floor_area);
features.winter_avg_temp = mean(source{:, ...
    {'december_avg_temp', 'january_avg_temp', 'february_avg_temp'}}, 2);
features.summer_avg_temp = mean(source{:, ...
    {'june_avg_temp', 'july_avg_temp', 'august_avg_temp'}}, 2);
features.summer_winter_temp_difference = ...
    features.summer_avg_temp - features.winter_avg_temp;
months = ["january", "february", "march", "april", "may", "june", ...
    "july", "august", "september", "october", "november", "december"];
features.yearly_temperature_range = ...
    max(source{:, months + "_max_temp"}, [], 2) - ...
    min(source{:, months + "_min_temp"}, [], 2);
features.total_degree_days = source.heating_degree_days + source.cooling_degree_days;
end

function encoding = fitFacilityEncoding(facility, logResponse, smoothing)
% alpha acts like this many observations at the global log-response mean.
[levels, ~, group] = unique(facility);
counts = accumarray(group, 1);
totals = accumarray(group, logResponse);
globalMean = mean(logResponse);
smoothedMean = (totals + smoothing * globalMean) ./ (counts + smoothing);
encoding = struct;
encoding.GlobalLogMean = globalMean;
encoding.Smoothing = smoothing;
encoding.FacilityStatistics = table(levels, counts, totals ./ counts, smoothedMean, ...
    'VariableNames', {'FacilityType', 'Count', 'MeanLogEUI', 'SmoothedLogEUI'});
end

function values = applyFacilityEncoding(facility, encoding)
% New or unknown facilities fall back to the fitting data's global mean.
[known, positions] = ismember(facility, encoding.FacilityStatistics.FacilityType);
values = repmat(encoding.GlobalLogMean, numel(facility), 1);
values(known) = encoding.FacilityStatistics.SmoothedLogEUI(positions(known));
end
