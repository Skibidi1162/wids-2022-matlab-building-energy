function [trainFeatures, validationFeatures, testFeatures, parameters] = ...
    wids_alternative_features(trainTable, validationTable, testTable)
%WIDS_ALTERNATIVE_FEATURES Six predictors built without energy-use targets.
% Facility area medians and interaction levels use the fitting rows only.
arguments
    trainTable table
    validationTable table
    testTable table
end

[facilityLevels, ~, group] = unique(string(trainTable.facility_type));
facilityMedianArea = accumarray(group, trainTable.floor_area, [], @median);
globalMedianArea = median(trainTable.floor_area);
interactionLevels = unique(string(trainTable.facility_type) + " | " + ...
    string(trainTable.State_Factor));
interactionLevels = [interactionLevels; "__unknown__"];
parameters = struct;
parameters.FacilityAreaMedians = table(facilityLevels, facilityMedianArea, ...
    'VariableNames', {'FacilityType', 'MedianArea'});
parameters.GlobalMedianArea = globalMedianArea;
parameters.InteractionLevels = interactionLevels;
parameters.AddedPredictors = ["relative_floor_area", "facility_state", ...
    "heating_share", "mean_monthly_temperature_spread", ...
    "severe_cold_share", "extreme_heat_share"];
parameters.UsesTargetValues = false;

trainFeatures = transformPredictors(trainTable, parameters);
validationFeatures = transformPredictors(validationTable, parameters);
testFeatures = transformPredictors(testTable, parameters);
parameters.PredictorNames = trainFeatures.Properties.VariableNames;
parameters.PredictorNames(strcmp(parameters.PredictorNames, 'site_eui')) = [];
testFeatures = testFeatures(:, parameters.PredictorNames);
end

function features = transformPredictors(source, parameters)
features = removevars(source, 'Year_Factor');
[known, positions] = ismember(string(source.facility_type), ...
    parameters.FacilityAreaMedians.FacilityType);
medianArea = repmat(parameters.GlobalMedianArea, height(source), 1);
medianArea(known) = parameters.FacilityAreaMedians.MedianArea(positions(known));
features.relative_floor_area = source.floor_area ./ medianArea;

interaction = string(source.facility_type) + " | " + string(source.State_Factor);
interaction(~ismember(interaction, parameters.InteractionLevels)) = "__unknown__";
features.facility_state = categorical(interaction, parameters.InteractionLevels);

features.heating_share = source.heating_degree_days ./ ...
    (source.heating_degree_days + source.cooling_degree_days + 1);
months = ["january", "february", "march", "april", "may", "june", ...
    "july", "august", "september", "october", "november", "december"];
monthlySpread = source{:, months + "_max_temp"} - source{:, months + "_min_temp"};
features.mean_monthly_temperature_spread = mean(monthlySpread, 2);
features.severe_cold_share = source.days_below_10F ./ max(source.days_below_30F, 1);
features.extreme_heat_share = source.days_above_100F ./ max(source.days_above_80F, 1);
end
