function signature = wids_model_signature()
%WIDS_MODEL_SIGNATURE Identify the frozen data, predictor list, and code.
folder = fileparts(mfilename('fullpath'));
dataFile = wids_data_file("train.csv");
digest = wids_sha256(dataFile);
signature = struct('DataFile',dataFile, ...
    'DataSHA256',digest, ...
    'MATLABVersion',version,'StudyVersion','other-local-models-v1');
sourceNames = {'wids_run_model_case.m','wids_fit_candidate.m','wids_model_summary.m', ...
    'wids_model_configs.m','wids_clean_split.m','wids_encode.m'};
for index=1:numel(sourceNames)
    field = matlab.lang.makeValidName(sourceNames{index});
    signature.Sources.(field) = fileread(wids_source_file(folder,sourceNames{index}));
end
selected = readtable(wids_shared_file("wids_selected_baseline_features.csv"), ...
    Delimiter=',',ReadVariableNames=true,TextType='string');
signature.PredictorNames = cellstr(selected.Predictor);
assert(numel(signature.PredictorNames)==59);
end
