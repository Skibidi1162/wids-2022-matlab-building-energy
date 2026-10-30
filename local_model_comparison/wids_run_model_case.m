function record = wids_run_model_case(configID,validationYear,resultDir)
%WIDS_RUN_MODEL_CASE One checkpointed model/fold case, safe to resume.
arguments
    configID (1,1) string
    validationYear (1,1) double {mustBeMember(validationYear,[4,5])}
    resultDir (1,1) string = ""
end
folder=fileparts(mfilename('fullpath'));
if strlength(resultDir)==0,resultDir=string(fullfile(folder,'results'));end
if ~isfolder(resultDir),mkdir(resultDir);end
configs=wids_model_configs();
index=find(string({configs.ID})==configID,1);
assert(~isempty(index),'Unknown model configuration ID.');
config=configs(index);
signature=wids_model_signature();
key=struct('Signature',signature,'Config',config,'ValidationYear',validationYear,'Seed',42);
checkpoint=fullfile(resultDir,sprintf('%s_year%d.mat',configID,validationYear));
if isfile(checkpoint)
    saved=load(checkpoint,'record');
    if isequaln(saved.record.Key,key) && strcmp(saved.record.Status,'ok')
        record=saved.record;
        fprintf('%s year %d: matching checkpoint reused.\n',configID,validationYear);
        wids_model_summary(resultDir,signature);
        return
    end
end
record=struct('Key',key,'ConfigID',configID,'Family',config.Family, ...
    'ValidationYear',validationYear,'FitRows',0,'ValidationRows',0, ...
    'SSE',NaN,'SAE',NaN,'RMSE',NaN,'MAE',NaN,'TrainingSeconds',NaN, ...
    'Status','error','ErrorMessage','');
model=[];preprocessing=struct;encoding=struct;diagnostics=struct;
validationIDs=[];predictions=[];
try
    raw=readtable(signature.DataFile);
    fittingRaw=raw(raw.Year_Factor<validationYear,:);
    validationRaw=raw(raw.Year_Factor==validationYear,:);
    assert(all(isfinite(fittingRaw.site_eui)) && all(isfinite(validationRaw.site_eui)));
    [fitting,validation,preprocessing]=wids_clean_split(fittingRaw,validationRaw);
    names=signature.PredictorNames;
    if ismember(config.Family,["forest","bagged"])
        X=fitting(:,names);Xval=validation(:,names);
        encoding=struct('Representation','native categorical table','PredictorNames',{names});
    else
        [X,Xval,encoding]=wids_encode(fitting,validation,names);
    end
    timer=tic;
    [model,diagnostics]=wids_fit_candidate(config,X,fitting.site_eui);
    record.TrainingSeconds=toc(timer);
    predictions=predict(model,Xval);
    assert(all(isfinite(predictions)));
    errors=predictions-validation.site_eui;
    record.SSE=sum(errors.^2);record.SAE=sum(abs(errors));
    assert(isfinite(record.SSE) && isfinite(record.SAE));
    record.FitRows=height(fitting);record.ValidationRows=height(validation);
    record.RMSE=sqrt(record.SSE/record.ValidationRows);
    record.MAE=record.SAE/record.ValidationRows;
    validationIDs=validationRaw.id;
    record.Status='ok';
catch problem
    record.ErrorMessage=getReport(problem,'basic','hyperlinks','off');
    fprintf('FAILED %s year %d: %s\n',configID,validationYear,problem.message);
end
temporary=[tempname(char(resultDir)),'.mat'];
save(temporary,'record','model','preprocessing','encoding','diagnostics', ...
    'validationIDs','predictions','-v7');
movefile(temporary,checkpoint,'f');
row=struct2table(rmfield(record,'Key'),AsArray=true);
row.ErrorMessage=string(regexprep(record.ErrorMessage,'[\r\n]+',' | '));
writetable(row,fullfile(resultDir,sprintf('%s_year%d.csv',configID,validationYear)),QuoteStrings=true);
wids_model_summary(resultDir,signature);
fprintf('%s year %d: %s; RMSE %.5f; MAE %.5f; %.1fs.\n', ...
    configID,validationYear,record.Status,record.RMSE,record.MAE,record.TrainingSeconds);
end
