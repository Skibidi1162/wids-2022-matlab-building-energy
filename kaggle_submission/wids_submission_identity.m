function identity = wids_submission_identity()
%WIDS_SUBMISSION_IDENTITY Stable data, preparation, and fixed-model identity.
folder=fileparts(mfilename('fullpath'));
dataFolder=wids_data_dir();
identity=struct('Study','WiDS-2022-HISTORY_RESIDUAL-full-data-v1', ...
    'MATLABVersion',version,'Seed',42,'ExpectedTrainRows',75757,'ExpectedTestRows',9705);
for name=["train","test","sample_solution"]
    path=fullfile(dataFolder,name+".csv");
    assert(isfile(path),'WiDS:SubmissionFile','Required input is missing: %s',path);
    identity.Inputs.(name)=struct('Path',path,'SHA256',fileSHA256(path));
end
selected=readtable(wids_shared_file("wids_selected_baseline_features.csv"), ...
    Delimiter=',',ReadVariableNames=true,TextType='string');
identity.BasePredictorNames=cellstr(selected.Predictor);
assert(numel(identity.BasePredictorNames)==59 && ...
    numel(unique(identity.BasePredictorNames))==59);
assert(~any(ismember(identity.BasePredictorNames,{'id','Year_Factor','site_eui'})));
identity.ModelConfigs.residual=struct('Method','LSBoost','Trees',300, ...
    'LearnRate',0.05,'MaxNumSplits',31,'MinLeafSize',5);
identity.ModelConfigs.boost=identity.ModelConfigs.residual;
identity.ModelConfigs.forest=struct('Method','Bag','Trees',100, ...
    'MaxNumSplits',511,'MinLeafSize',5,'Mtry',20,'Reproducible',true);
identity.SelectedMethod='HISTORY_RESIDUAL';identity.FallbackForestWeight=0.5;
identity.PredictionAdjustment='none';
sourceNames={'wids_submission_identity.m','wids_submission_prepare.m', ...
    'wids_submission_atomic_save.m','wids_sha256.m','wids_clean_split.m', ...
    'wids_past_building_features.m','wids_selected_baseline_features.csv'};
for index=1:numel(sourceNames)
    field=matlab.lang.makeValidName(sourceNames{index});
    identity.Sources.(field)=fileread(wids_source_file(folder,sourceNames{index}));
end
end

function digest = fileSHA256(path)
digest = wids_sha256(path);
end
