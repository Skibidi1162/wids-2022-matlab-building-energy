function [fitClean, validationClean, parameters] = wids_clean_split(fitRaw, validationRaw)
%WIDS_CLEAN_SPLIT Apply the project cleaning rules to an explicit time split.
% Learn medians and category levels from fitRaw only. Keep positive historic
% construction years; treat year zero as unknown. Targets are never imputed.
arguments
    fitRaw table
    validationRaw table
end

parameters = struct;
parameters.DroppedPredictors = ["direction_max_wind_speed", ...
    "direction_peak_wind_speed", "max_wind_speed", "days_with_fog"];
removeNames = ["id", parameters.DroppedPredictors];
fitClean = removevars(fitRaw, removeNames);
validationClean = removevars(validationRaw, removeNames);
fitClean.year_built(fitClean.year_built == 0) = NaN;
validationClean.year_built(validationClean.year_built == 0) = NaN;

for name = ["State_Factor", "building_class", "facility_type"]
    fitText = strtrim(string(fitClean.(name)));
    validationText = strtrim(string(validationClean.(name)));
    levels = unique(fitText(~ismissing(fitText) & fitText ~= ""));
    levels = unique([levels; "__unknown__"], 'stable');
    fitText(~ismember(fitText, levels)) = "__unknown__";
    validationText(~ismember(validationText, levels)) = "__unknown__";
    fitClean.(name) = categorical(fitText, levels);
    validationClean.(name) = categorical(validationText, levels);
    parameters.CategoryLevels.(name) = levels;
end

for name = ["year_built", "energy_star_rating"]
    fitMissing = ismissing(fitClean.(name));
    validationMissing = ismissing(validationClean.(name));
    flagName = name + "_missing";
    fitClean.(flagName) = fitMissing;
    validationClean.(flagName) = validationMissing;
    replacement = median(fitClean.(name), 'omitmissing');
    if ~isfinite(replacement)
        error('WiDS:MissingMedian', 'No finite fitting median available for %s.', name);
    end
    fitClean.(name)(fitMissing) = replacement;
    validationClean.(name)(validationMissing) = replacement;
    parameters.Medians.(name) = replacement;
end
end
