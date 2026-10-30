function info = wids_submission_fit(kind)
%WIDS_SUBMISSION_FIT Fit one full-data model per invocation.
% Run separately for "residual", "boost", and "forest" after preparation.
arguments
    kind (1,1) string {mustBeMember(kind,["residual","boost","forest"])}
end
folder=fileparts(mfilename('fullpath'));previousFolder=pwd;
restoreFolder=onCleanup(@()cd(previousFolder));cd(folder);
identity=wids_submission_identity();
preparedFile=fullfile(folder,'checkpoints','prepared.mat');
assert(isfile(preparedFile),'WiDS:SubmissionStage','Run wids_submission_prepare first.');
prepared=load(preparedFile,'key','metadata');
expectedPreparation=struct('Identity',identity,'Stage','prepare');
assert(isequaln(prepared.key,expectedPreparation), ...
    'WiDS:SubmissionProvenance','Preparation no longer matches inputs, code, or configuration.');
config=identity.ModelConfigs.(kind);
key=struct('PreparedKey',prepared.key,'Stage','fit','Kind',kind, ...
    'Config',config,'RunnerSource',fileread([mfilename('fullpath'),'.m']));
checkpoint=fullfile(folder,'checkpoints',kind+"_model.mat");
if isfile(checkpoint)
    saved=load(checkpoint,'record');
    if isequaln(saved.record.Key,key) && strcmp(saved.record.Status,'ok')
        info=rmfield(saved.record,'Key');
        fprintf('Matching %s model checkpoint reused.\n',kind);return
    end
end
rng(identity.Seed,'twister');
if kind=="residual"
    data=load(preparedFile,'XHistory','fitHasHistory','residualTarget');
    X=data.XHistory(data.fitHasHistory,:);y=data.residualTarget;
    tree=templateTree(MaxNumSplits=config.MaxNumSplits,MinLeafSize=config.MinLeafSize);
elseif kind=="boost"
    data=load(preparedFile,'XBase','y');X=data.XBase;y=data.y;
    tree=templateTree(MaxNumSplits=config.MaxNumSplits,MinLeafSize=config.MinLeafSize);
else
    data=load(preparedFile,'XBase','y');X=data.XBase;y=data.y;
    tree=templateTree(MaxNumSplits=config.MaxNumSplits,MinLeafSize=config.MinLeafSize, ...
        NumVariablesToSample=config.Mtry,Reproducible=config.Reproducible);
end
assert(height(X)==numel(y) && all(isfinite(y)) && ~any(ismissing(X),'all'));
assert(~any(ismember(X.Properties.VariableNames,{'id','Year_Factor','site_eui'})));
timer=tic;
if kind=="forest"
    trained=fitrensemble(X,y,Method=config.Method,NumLearningCycles=config.Trees, ...
        Learners=tree,Options=statset('UseParallel',false));
else
    trained=fitrensemble(X,y,Method=config.Method,NumLearningCycles=config.Trees, ...
        LearnRate=config.LearnRate,Learners=tree,Options=statset('UseParallel',false));
end
model=compact(trained);trainingSeconds=toc(timer);
assert(numel(model.Trained)==config.Trees);
record=struct('Key',key,'Status','ok','Kind',kind,'FitRows',height(X), ...
    'PredictorCount',width(X),'CompletedTrees',numel(model.Trained), ...
    'TrainingSeconds',trainingSeconds,'Seed',identity.Seed,'Config',config);
record.PredictorNames=X.Properties.VariableNames;
wids_submission_atomic_save(checkpoint,struct('record',record,'model',model));
info=rmfield(record,'Key');
fprintf('Saved %s model: %d rows, %d predictors, %d trees, %.1fs.\n', ...
    kind,height(X),width(X),numel(model.Trained),trainingSeconds);
end
