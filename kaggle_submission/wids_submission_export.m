function info = wids_submission_export()
%WIDS_SUBMISSION_EXPORT Predict the exact selected method and write Kaggle CSV.
folder=fileparts(mfilename('fullpath'));previousFolder=pwd;
restoreFolder=onCleanup(@()cd(previousFolder));cd(folder);
identity=wids_submission_identity();
preparedFile=fullfile(folder,'checkpoints','prepared.mat');
assert(isfile(preparedFile),'WiDS:SubmissionStage','Run preparation and all three model fits first.');
prepared=load(preparedFile,'key','metadata','XTestBase','XTestHistory', ...
    'testHasHistory','testLatestEUI','testIDs','sampleIDs','sampleToTest');
expectedPreparation=struct('Identity',identity,'Stage','prepare');
assert(isequaln(prepared.key,expectedPreparation));
models=struct;modelRecords=struct;
fitSource=fileread(fullfile(folder,'wids_submission_fit.m'));
for kind=["residual","boost","forest"]
    file=fullfile(folder,'checkpoints',kind+"_model.mat");
    assert(isfile(file),'WiDS:SubmissionStage','Missing model stage: %s',kind);
    saved=load(file,'record','model');
    config=identity.ModelConfigs.(kind);
    expected=struct('PreparedKey',prepared.key,'Stage','fit','Kind',kind, ...
        'Config',config,'RunnerSource',fitSource);
    assert(isequaln(saved.record.Key,expected) && strcmp(saved.record.Status,'ok'));
    assert(saved.record.Seed==identity.Seed && saved.record.CompletedTrees==config.Trees);
    if kind=="residual"
        names=prepared.metadata.HistoryPredictorNames;
        fitRows=prepared.metadata.ResidualFitRows;
    else
        names=prepared.metadata.BasePredictorNames;fitRows=identity.ExpectedTrainRows;
    end
    assert(saved.record.FitRows==fitRows && saved.record.PredictorCount==numel(names));
    assert(isequal(saved.record.PredictorNames,names));
    assert(isequal(saved.model.PredictorNames,names));
    models.(kind)=saved.model;modelRecords.(kind)=saved.record;
end
assert(~any(ismember(prepared.XTestBase.Properties.VariableNames,{'id','Year_Factor','site_eui'})));
assert(~any(ismember(prepared.XTestHistory.Properties.VariableNames,{'id','Year_Factor','site_eui'})));
boostPredictions=predict(models.boost,prepared.XTestBase);
forestPredictions=predict(models.forest,prepared.XTestBase);
assert(isequal(size(boostPredictions),size(prepared.testIDs)) && all(isfinite(boostPredictions)));
assert(isequal(size(forestPredictions),size(prepared.testIDs)) && all(isfinite(forestPredictions)));
fallbackPredictions=(1-identity.FallbackForestWeight)*boostPredictions+ ...
    identity.FallbackForestWeight*forestPredictions;
predictions=fallbackPredictions;hasHistory=prepared.testHasHistory;
assert(isequal(size(hasHistory),size(predictions)));
residualPredictions=NaN(size(predictions));
if any(hasHistory)
    residualPredictions(hasHistory)=predict(models.residual,prepared.XTestHistory(hasHistory,:));
    assert(all(isfinite(residualPredictions(hasHistory))) && ...
        all(isfinite(prepared.testLatestEUI(hasHistory))));
    predictions(hasHistory)=prepared.testLatestEUI(hasHistory)+residualPredictions(hasHistory);
end
assert(numel(predictions)==identity.ExpectedTestRows && all(isfinite(predictions)));
assert(isequal(predictions(~hasHistory),fallbackPredictions(~hasHistory)));
assert(isequal(prepared.testIDs(prepared.sampleToTest),prepared.sampleIDs));
submission=table(prepared.sampleIDs,predictions(prepared.sampleToTest), ...
    'VariableNames',{'id','site_eui'});
assert(isequal(submission.Properties.VariableNames,{'id','site_eui'}));
assert(height(submission)==identity.ExpectedTestRows && numel(unique(submission.id))==height(submission));
assert(isequal(submission.id,prepared.sampleIDs) && all(isfinite(submission.site_eui)));
assert(submission.id(1)==prepared.sampleIDs(1) && ...
    submission.site_eui(1)==predictions(prepared.sampleToTest(1)));

csvPath=fullfile(folder,'wids_history_residual_submission.csv');
temporary=[tempname(folder),'.csv'];
writeExactCSV(temporary,submission);
roundTrip=readtable(temporary);
assert(isequal(roundTrip.Properties.VariableNames,{'id','site_eui'}));
assert(isequal(roundTrip.id,submission.id) && height(roundTrip)==height(submission));
assert(all(isfinite(roundTrip.site_eui)) && isequal(roundTrip.site_eui,submission.site_eui), ...
    'WiDS:SubmissionRoundTrip','Exported predictions did not round-trip exactly.');
csvSHA256=fileSHA256(temporary);
movefile(temporary,csvPath,'f');
key=struct('PreparedKey',prepared.key,'Stage','export', ...
    'ResidualKey',modelRecords.residual.Key,'BoostKey',modelRecords.boost.Key, ...
    'ForestKey',modelRecords.forest.Key,'RunnerSource',fileread([mfilename('fullpath'),'.m']));
record=struct('Key',key,'Status','ok','SelectedMethod',identity.SelectedMethod, ...
    'CSVPath',csvPath,'CSVSHA256',csvSHA256,'TrainRows',identity.ExpectedTrainRows, ...
    'SubmissionRows',height(submission),'HistoryRows',sum(hasHistory), ...
    'NoHistoryRows',sum(~hasHistory),'FirstID',submission.id(1), ...
    'FirstPrediction',submission.site_eui(1),'MinPrediction',min(predictions), ...
    'MaxPrediction',max(predictions),'NegativePredictionRows',sum(predictions<0), ...
    'PredictionAdjustment','none');
payload=struct('record',record,'modelRecords',modelRecords,'modelMetadata',prepared.metadata, ...
    'submission',submission,'testIDs',prepared.testIDs,'predictions',predictions, ...
    'fallbackPredictions',fallbackPredictions,'boostPredictions',boostPredictions, ...
    'forestPredictions',forestPredictions,'residualPredictions',residualPredictions, ...
    'hasHistory',hasHistory);
wids_submission_atomic_save(fullfile(folder,'checkpoints','export.mat'),payload);
info=rmfield(record,'Key');
fprintf('Validated and saved %d rows to %s.\n',height(submission),csvPath);
end

function writeExactCSV(path,submission)
% IDs are validated integer doubles; 17 significant digits preserve each
% prediction's stored double value. No clipping or calibration is applied.
fid=fopen(path,'w');assert(fid>=0);closeFile=onCleanup(@()fclose(fid));
fprintf(fid,'id,site_eui\n');
fprintf(fid,'%.0f,%.17g\n',[double(submission.id),submission.site_eui].');
end

function digest = fileSHA256(path)
digest = wids_sha256(path);
end
