function metadata = wids_submission_prepare()
%WIDS_SUBMISSION_PREPARE Fit full-labeled preprocessing and past-only history.
folder=fileparts(mfilename('fullpath'));previousFolder=pwd;
restoreFolder=onCleanup(@()cd(previousFolder));cd(folder);
assert(strcmpi(which('wids_clean_split'),fullfile(folder,'wids_clean_split.m')));
assert(strcmpi(which('wids_past_building_features'),fullfile(folder,'wids_past_building_features.m')));
identity=wids_submission_identity();key=struct('Identity',identity,'Stage','prepare');
checkpoint=fullfile(folder,'checkpoints','prepared.mat');
if isfile(checkpoint)
    saved=load(checkpoint,'key','metadata');
    if isequaln(saved.key,key)
        metadata=saved.metadata;fprintf('Matching preparation checkpoint reused.\n');return
    end
end
train=readtable(identity.Inputs.train.Path);
test=readtable(identity.Inputs.test.Path);
sample=readtable(identity.Inputs.sample_solution.Path);
assert(height(train)==identity.ExpectedTrainRows && height(test)==identity.ExpectedTestRows);
assert(height(sample)==height(test));
assert(isequal(sample.Properties.VariableNames,{'id','site_eui'}));
validateIDs(train.id,height(train));validateIDs(test.id,height(test));
validateIDs(sample.id,height(sample));
assert(isempty(intersect(train.id,test.id)),'WiDS:SubmissionIDs','Train/test IDs overlap.');
assert(all(isfinite(train.site_eui)));
assert(~ismember('site_eui',test.Properties.VariableNames), ...
    'WiDS:SubmissionTarget','Test data must not contain a response column.');
assert(isequal(unique(train.Year_Factor),(1:6)') && all(test.Year_Factor==7));
[found,sampleToTest]=ismember(sample.id,test.id);
assert(all(found) && numel(unique(sampleToTest))==height(test));

[fitHistory,testHistory,historyAudit]=wids_past_building_features(train,test);
[fitClean,testClean,preprocessing]=wids_clean_split(train,test);
XBase=fitClean(:,identity.BasePredictorNames);
XTestBase=testClean(:,identity.BasePredictorNames);
assert(width(XBase)==59 && width(XTestBase)==59);
assert(~any(ismissing(XBase),'all') && ~any(ismissing(XTestBase),'all'));
XHistory=XBase;XTestHistory=XTestBase;historyPreprocessing=struct;
assert(width(fitHistory)==8 && width(testHistory)==8);
for index=1:width(fitHistory)
    name=fitHistory.Properties.VariableNames{index};
    a=fitHistory.(name);b=testHistory.(name);
    missingA=~isfinite(a);missingB=~isfinite(b);available=a(~missingA);
    medianValue=0;if ~isempty(available),medianValue=median(available);end
    historyPreprocessing.(name)=medianValue;
    a(missingA)=medianValue;b(missingB)=medianValue;
    XHistory.(name)=a;XTestHistory.(name)=b;
    if ~ismember(name,{'history_available','history_years'})
        XHistory.([name,'_missing'])=double(missingA);
        XTestHistory.([name,'_missing'])=double(missingB);
    end
end
assert(width(XHistory)==73 && width(XTestHistory)==73);
assert(~any(ismissing(XHistory),'all') && ~any(ismissing(XTestHistory),'all'));
for names={XBase.Properties.VariableNames,XHistory.Properties.VariableNames}
    assert(~any(ismember(names{1},{'id','Year_Factor','site_eui'})));
end
fitHasHistory=fitHistory.history_available==1;
testHasHistory=testHistory.history_available==1;
assert(any(fitHasHistory));
y=train.site_eui;
residualTarget=y(fitHasHistory)-fitHistory.history_latest_eui(fitHasHistory);
assert(all(isfinite(residualTarget)));
testLatestEUI=testHistory.history_latest_eui;
assert(all(isfinite(testLatestEUI(testHasHistory))));
metadata=struct('SelectedMethod',identity.SelectedMethod,'TrainRows',height(train), ...
    'TestRows',height(test),'ResidualFitRows',sum(fitHasHistory), ...
    'TestHistoryRows',sum(testHasHistory),'TestNoHistoryRows',sum(~testHasHistory), ...
    'BasePredictorCount',width(XBase),'HistoryPredictorCount',width(XHistory),'Seed',identity.Seed);
metadata.BasePredictorNames=XBase.Properties.VariableNames;
metadata.HistoryPredictorNames=XHistory.Properties.VariableNames;
metadata.PreprocessingFit='all labeled training rows only';
metadata.HistoryRule='strictly earlier fitting years, raw five-key match, duplicate-year means';
payload=struct('key',key,'metadata',metadata,'XBase',XBase,'XTestBase',XTestBase, ...
    'XHistory',XHistory,'XTestHistory',XTestHistory,'y',y, ...
    'residualTarget',residualTarget,'fitHasHistory',fitHasHistory, ...
    'testHasHistory',testHasHistory,'testLatestEUI',testLatestEUI, ...
    'testIDs',test.id,'sampleIDs',sample.id,'sampleToTest',sampleToTest, ...
    'preprocessing',preprocessing,'historyPreprocessing',historyPreprocessing, ...
    'historyAudit',historyAudit);
wids_submission_atomic_save(checkpoint,payload);
fprintf('Prepared %d training rows, %d test rows; %d test rows have history.\n', ...
    height(train),height(test),sum(testHasHistory));
end

function validateIDs(ids,n)
assert(isnumeric(ids) && isequal(size(ids),[n,1]) && all(isfinite(ids)));
assert(all(ids==fix(ids) & abs(ids)<=flintmax) && numel(unique(ids))==n, ...
    'WiDS:SubmissionIDs','IDs must be unique, exactly represented integers.');
end
