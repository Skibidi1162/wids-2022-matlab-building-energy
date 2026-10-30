function signature = wids_model_signature()
%WIDS_MODEL_SIGNATURE Identify the frozen data, predictor list, and code.
folder = fileparts(mfilename('fullpath'));
dataFile = wids_data_file("train.csv");
stream = System.IO.File.Open(dataFile,System.IO.FileMode.Open, ...
    System.IO.FileAccess.Read,System.IO.FileShare.ReadWrite);
closeStream = onCleanup(@()stream.Dispose());
algorithm = System.Security.Cryptography.SHA256.Create();
closeAlgorithm = onCleanup(@()algorithm.Dispose());
bytes = uint8(algorithm.ComputeHash(stream));
signature = struct('DataFile',dataFile, ...
    'DataSHA256',lower(reshape(dec2hex(bytes,2).',1,[])), ...
    'MATLABVersion',version,'StudyVersion','other-local-models-v1');
sourceNames = {'wids_run_model_case.m','wids_fit_candidate.m','wids_model_summary.m', ...
    'wids_model_configs.m','wids_clean_split.m','nscc_encode.m'};
for index=1:numel(sourceNames)
    field = matlab.lang.makeValidName(sourceNames{index});
    signature.Sources.(field) = fileread(fullfile(folder,sourceNames{index}));
end
selected = readtable(fullfile(folder,'wids_selected_baseline_features.csv'), ...
    Delimiter=',',ReadVariableNames=true,TextType='string');
signature.PredictorNames = cellstr(selected.Predictor);
assert(numel(signature.PredictorNames)==59);
end
