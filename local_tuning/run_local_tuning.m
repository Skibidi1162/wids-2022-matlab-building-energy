function summary = run_local_tuning(dataFile, resultDir, configIDs)
%RUN_LOCAL_TUNING Checkpointed local LSBoost search on frozen predictors.
% Fits only years < 4 or < 5 and scores only year 4 or year 5.
% Example: run_local_tuning("","","L01") runs the anchor; cached successful
% folds are reused only when data, code, MATLAB version, and settings match.
arguments
    dataFile (1,1) string = ""
    resultDir (1,1) string = ""
    configIDs string = strings(0)
end
folder = fileparts(mfilename('fullpath'));
if strlength(dataFile) == 0
    dataFile = wids_data_file("train.csv");
end
if strlength(resultDir) == 0
    resultDir = string(fullfile(folder,'results'));
end
if ~isfolder(resultDir)
    mkdir(resultDir);
end
configs = wids_local_configs();
if isempty(configIDs)
    configIDs = configs.ConfigID;
end
if ~all(ismember(configIDs,configs.ConfigID))
    error('WiDS:UnknownConfig','Requested configuration ID is not in the manifest.');
end
selected = readtable(wids_shared_file("wids_selected_baseline_features.csv"), ...
    Delimiter=',',ReadVariableNames=true,TextType='string');
predictorNames = cellstr(selected.Predictor);
if numel(predictorNames) ~= 59 || any(ismember(predictorNames,{'id','Year_Factor','site_eui'}))
    error('WiDS:InvalidPredictors','Expected the frozen 59-predictor baseline.');
end
dataSHA256 = fileSHA256(dataFile);
raw = readtable(dataFile);
signature = struct('DataSHA256',dataSHA256,'MATLABVersion',version, ...
    'RunnerSource',fileread([mfilename('fullpath'),'.m']), ...
    'CleaningSource',fileread(wids_shared_file("wids_clean_split.m")), ...
    'SummarySource',fileread(fullfile(folder,'wids_local_summary.m')), ...
    'PredictorNames',{predictorNames});
writetable(configs,fullfile(resultDir,'local_tuning_manifest.csv'));
save(fullfile(resultDir,'local_run_identity.mat'),'signature','configs');
records = cell(height(configs),2);

%% Load matching successful checkpoints for all configurations
for configIndex = 1:height(configs)
    for foldIndex = 1:2
        validationYear = foldIndex+3;
        checkpoint = checkpointPath(resultDir,configs.ConfigID(configIndex),validationYear);
        key = struct('Signature',signature,'Config',table2struct(configs(configIndex,:)), ...
            'ValidationYear',validationYear,'Seed',42);
        if isfile(checkpoint)
            saved = load(checkpoint,'record');
            if isfield(saved,'record') && isequaln(saved.record.Key,key) ...
                    && strcmp(saved.record.Status,'ok')
                records{configIndex,foldIndex} = saved.record;
            end
        end
    end
end
summary = wids_local_summary(records,configs);
writetable(summary,fullfile(resultDir,'local_tuning_results.csv'));

%% Train requested configurations; all preprocessing is split-specific
for configIndex = 1:height(configs)
    if ~ismember(configs.ConfigID(configIndex),configIDs)
        continue
    end
    for foldIndex = 1:2
        validationYear = foldIndex+3;
        if ~isempty(records{configIndex,foldIndex})
            fprintf('%s year %d: matching checkpoint reused.\n', ...
                configs.ConfigID(configIndex),validationYear);
            continue
        end
        key = struct('Signature',signature,'Config',table2struct(configs(configIndex,:)), ...
            'ValidationYear',validationYear,'Seed',42);
        record = struct('Key',key,'ConfigID',configs.ConfigID(configIndex), ...
            'ValidationYear',validationYear,'FitRows',0,'ValidationRows',0, ...
            'SSE',NaN,'SAE',NaN,'RMSE',NaN,'MAE',NaN,'TrainingSeconds',NaN, ...
            'Status','error','ErrorMessage','');
        model = [];
        preprocessing = struct;
        validationIDs = [];
        predictions = [];
        try
            fittingRaw = raw(raw.Year_Factor < validationYear,:);
            validationRaw = raw(raw.Year_Factor == validationYear,:);
            if isempty(fittingRaw) || isempty(validationRaw) || ...
                    any(~isfinite(fittingRaw.site_eui)) || ...
                    any(~isfinite(validationRaw.site_eui))
                error('WiDS:InvalidResponses','Fitting and validation targets must be present and finite.');
            end
            [fitting,validation,preprocessing] = wids_clean_split(fittingRaw,validationRaw);
            fitX = fitting(:,predictorNames);
            validationX = validation(:,predictorNames);
            if any(ismissing(fitX),'all') || any(ismissing(validationX),'all')
                error('WiDS:MissingInputs','Prepared predictor table contains missing values.');
            end
            rng(42,'twister');
            tree = templateTree(MaxNumSplits=configs.MaxNumSplits(configIndex), ...
                MinLeafSize=configs.MinLeafSize(configIndex), ...
                NumVariablesToSample='all',Reproducible=true);
            timer = tic;
            trained = fitrensemble(fitX,fitting.site_eui,Method='LSBoost', ...
                NumLearningCycles=configs.Trees(configIndex), ...
                LearnRate=configs.LearnRate(configIndex),Learners=tree);
            record.TrainingSeconds = toc(timer);
            model = compact(trained);
            predictions = predict(model,validationX);
            if any(~isfinite(predictions))
                error('WiDS:NonfinitePredictions','Model produced nonfinite validation predictions.');
            end
            errors = predictions-validation.site_eui;
            validationIDs = validationRaw.id;
            record.FitRows = height(fitting);
            record.ValidationRows = height(validation);
            record.SSE = sum(errors.^2);
            record.SAE = sum(abs(errors));
            if ~isfinite(record.SSE) || ~isfinite(record.SAE)
                error('WiDS:NonfiniteMetrics','Aggregate validation errors must be finite.');
            end
            record.RMSE = sqrt(record.SSE/record.ValidationRows);
            record.MAE = record.SAE/record.ValidationRows;
            record.Status = 'ok';
        catch problem
            record.ErrorMessage = getReport(problem,'basic','hyperlinks','off');
            fprintf('FAILED %s year %d: %s\n',record.ConfigID,validationYear,problem.message);
        end
        checkpoint = checkpointPath(resultDir,record.ConfigID,validationYear);
        temporary = [tempname(char(resultDir)),'.mat'];
        save(temporary,'record','model','preprocessing','validationIDs','predictions','-v7');
        movefile(temporary,checkpoint,'f');
        records{configIndex,foldIndex} = record;
        fprintf('%s year %d: %s, RMSE %.5f, %.1fs.\n', ...
            record.ConfigID,validationYear,record.Status,record.RMSE,record.TrainingSeconds);
        exportRecords(records,resultDir);
        summary = wids_local_summary(records,configs);
        writetable(summary,fullfile(resultDir,'local_tuning_results.csv'));
    end
end
summary = wids_local_summary(records,configs);
writetable(summary,fullfile(resultDir,'local_tuning_results.csv'));
if ~isempty(summary)
    disp(summary);
end
end

function path = checkpointPath(folder,configID,validationYear)
path = fullfile(folder,sprintf('%s_year%d.mat',configID,validationYear));
end

function exportRecords(records,folder)
rows = table;
for index = 1:numel(records)
    record = records{index};
    if isempty(record)
        continue
    end
    row = table(string(record.ConfigID),record.ValidationYear,record.FitRows, ...
        record.ValidationRows,record.SSE,record.SAE,record.RMSE,record.MAE, ...
        record.TrainingSeconds,string(record.Status), ...
        string(regexprep(record.ErrorMessage,'[\r\n]+',' | ')), ...
        'VariableNames',{'ConfigID','ValidationYear','FitRows','ValidationRows', ...
        'SSE','SAE','RMSE','MAE','TrainingSeconds','Status','ErrorMessage'});
    rows = [rows;row]; %#ok<AGROW>
end
writetable(rows,fullfile(folder,'local_tuning_fold_results.csv'),QuoteStrings=true);
end

function digest = fileSHA256(path)
digest = wids_sha256(path);
end
