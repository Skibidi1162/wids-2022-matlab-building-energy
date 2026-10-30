function records = run_building_history_case(validationYear)
%RUN_BUILDING_HISTORY_CASE Test past-only building histories on an existing fold.
arguments
    validationYear (1,1) double {mustBeMember(validationYear,[4,5])}
end
folder=fileparts(mfilename('fullpath'));resultDir=fullfile(folder,'results');
signature=wids_model_signature();
raw=readtable(signature.DataFile);
fallback=wids_verified_history_fallback(folder,signature,raw,validationYear);
key=struct('Signature',signature,'ValidationYear',validationYear,'Seed',42, ...
    'RunnerSource',fileread([mfilename('fullpath'),'.m']), ...
    'HistorySource',fileread(fullfile(folder,'wids_past_building_features.m')), ...
    'FallbackSource',fileread(fullfile(folder,'wids_verified_history_fallback.m')), ...
    'FallbackBaseKeys',{fallback.record.BaseKeys},'FallbackForestWeight',0.5);
checkpoint=fullfile(resultDir,sprintf('HISTORY_year%d.mat',validationYear));
if isfile(checkpoint)
    saved=load(checkpoint,'key','records');
    if isequaln(saved.key,key),records=saved.records;disp(records);return,end
end
fittingRaw=raw(raw.Year_Factor<validationYear,:);
validationRaw=raw(raw.Year_Factor==validationYear,:);
assert(all(isfinite(fittingRaw.site_eui)) && all(isfinite(validationRaw.site_eui)));
[fitHistory,valHistory,audit]=wids_past_building_features(fittingRaw, ...
    removevars(validationRaw,'site_eui'));
hasHistory=valHistory.history_available==1;
fitHasHistory=fitHistory.history_available==1;
latest=valHistory.history_latest_eui;
[fitting,validation,preprocessing]=wids_clean_split(fittingRaw,validationRaw);
X=fitting(:,signature.PredictorNames);Xval=validation(:,signature.PredictorNames);
historyPreprocessing=struct;
for index=1:width(fitHistory)
    name=fitHistory.Properties.VariableNames{index};
    a=fitHistory.(name);b=valHistory.(name);
    missingA=~isfinite(a);missingB=~isfinite(b);
    available=a(~missingA);medianValue=0;
    if ~isempty(available),medianValue=median(available);end
    historyPreprocessing.(name)=medianValue;
    a(missingA)=medianValue;b(missingB)=medianValue;
    X.(name)=a;Xval.(name)=b;
    if ~ismember(name,{'history_available','history_years'})
        X.([name,'_missing'])=double(missingA);
        Xval.([name,'_missing'])=double(missingB);
    end
end
predictions=struct;models=struct;fitSeconds=zeros(1,3);
predictions.HISTORY_LATEST=fallback.predictions;
predictions.HISTORY_LATEST(hasHistory)=latest(hasHistory);
tree=templateTree(MaxNumSplits=31,MinLeafSize=5);
rng(42,'twister');timer=tic;
models.HISTORY_DIRECT=compact(fitrensemble(X,fitting.site_eui,Method='LSBoost', ...
    NumLearningCycles=300,LearnRate=0.05,Learners=tree,Options=statset('UseParallel',false)));
fitSeconds(2)=toc(timer);
predictions.HISTORY_DIRECT=predict(models.HISTORY_DIRECT,Xval);
assert(any(fitHasHistory),'No fitting rows have previous history.');
delta=fitting.site_eui(fitHasHistory)-fitHistory.history_latest_eui(fitHasHistory);
assert(all(isfinite(delta)));
rng(42,'twister');timer=tic;
models.HISTORY_RESIDUAL=compact(fitrensemble(X(fitHasHistory,:),delta,Method='LSBoost', ...
    NumLearningCycles=300,LearnRate=0.05,Learners=tree,Options=statset('UseParallel',false)));
fitSeconds(3)=toc(timer);
predictions.HISTORY_RESIDUAL=fallback.predictions;
predictions.HISTORY_RESIDUAL(hasHistory)=latest(hasHistory)+ ...
    predict(models.HISTORY_RESIDUAL,Xval(hasHistory,:));
records=table;
methods=fieldnames(predictions);
for index=1:numel(methods)
    method=methods{index};prediction=predictions.(method);
    assert(isequal(size(prediction),size(validation.site_eui)) && all(isfinite(prediction)));
    residual=prediction-validation.site_eui;
    SSE=sum(residual.^2);SAE=sum(abs(residual));
    assert(isfinite(SSE) && isfinite(SAE));
    row=table(string(method),validationYear,height(fitting),height(validation), ...
        sum(hasHistory),SSE,SAE,sqrt(SSE/height(validation)),SAE/height(validation), ...
        sqrt(mean(residual(hasHistory).^2)),sqrt(mean(residual(~hasHistory).^2)),fitSeconds(index), ...
        'VariableNames',{'Method','ValidationYear','FitRows','ValidationRows','HistoryRows', ...
        'SSE','SAE','RMSE','MAE','HistoryRMSE','NoHistoryRMSE','TrainingSeconds'});
    records=[records;row]; %#ok<AGROW>
end
validationIDs=validationRaw.id;actual=validation.site_eui;
fallbackPredictions=fallback.predictions;
predictorNames=X.Properties.VariableNames;
temporary=[tempname(resultDir),'.mat'];
save(temporary,'key','records','models','preprocessing','historyPreprocessing', ...
    'predictorNames','audit','validationIDs','actual','hasHistory','predictions', ...
    'fallbackPredictions','-v7');
movefile(temporary,checkpoint,'f');
writetable(records,fullfile(resultDir,sprintf('HISTORY_year%d.csv',validationYear)));
disp(records);disp(audit);
end
