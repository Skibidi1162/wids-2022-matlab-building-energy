function record = run_longer_network_case(validationYear)
%RUN_LONGER_NETWORK_CASE Give the iteration-capped network a larger fit budget.
arguments
    validationYear (1,1) double {mustBeMember(validationYear,[4,5])}
end
folder=fileparts(mfilename('fullpath'));resultDir=fullfile(folder,'results');
configs=wids_model_configs();config=configs(string({configs.ID})=="NET64x32");
config.ID="NET64x32_1000";config.Parameters.IterationLimit=1000;
signature=wids_model_signature();
key=struct('Signature',signature,'Config',config,'ValidationYear',validationYear, ...
    'Seed',42,'RunnerSource',fileread([mfilename('fullpath'),'.m']));
checkpoint=fullfile(resultDir,sprintf('%s_year%d.mat',config.ID,validationYear));
if isfile(checkpoint)
    saved=load(checkpoint,'record');
    if isequaln(saved.record.Key,key) && strcmp(saved.record.Status,'ok')
        record=saved.record;disp(record);return
    end
end
raw=readtable(signature.DataFile);
fittingRaw=raw(raw.Year_Factor<validationYear,:);
validationRaw=raw(raw.Year_Factor==validationYear,:);
assert(all(isfinite(fittingRaw.site_eui)) && all(isfinite(validationRaw.site_eui)));
[fitting,validation,preprocessing]=wids_clean_split(fittingRaw,validationRaw);
[X,Xval,encoding]=nscc_encode(fitting,validation,signature.PredictorNames);
timer=tic;[model,diagnostics]=wids_fit_candidate(config,X,fitting.site_eui);
trainingSeconds=toc(timer);predictions=predict(model,Xval);
assert(isequal(size(predictions),size(validation.site_eui)) && all(isfinite(predictions)));
residual=predictions-validation.site_eui;
SSE=sum(residual.^2);SAE=sum(abs(residual));assert(isfinite(SSE) && isfinite(SAE));
record=struct('Key',key,'ConfigID',config.ID,'Family',config.Family, ...
    'ValidationYear',validationYear,'FitRows',height(fitting),'ValidationRows',height(validation), ...
    'SSE',SSE,'SAE',SAE,'RMSE',sqrt(SSE/height(validation)), ...
    'MAE',SAE/height(validation),'TrainingSeconds',trainingSeconds,'Status','ok', ...
    'Iterations',diagnostics.ConvergenceInfo.Iterations, ...
    'Termination',string(diagnostics.ConvergenceInfo.ConvergenceCriterion));
validationIDs=validationRaw.id;
temporary=[tempname(resultDir),'.mat'];
save(temporary,'record','model','preprocessing','encoding','diagnostics', ...
    'validationIDs','predictions','-v7');movefile(temporary,checkpoint,'f');
writetable(struct2table(rmfield(record,'Key'),AsArray=true), ...
    fullfile(resultDir,sprintf('%s_year%d.csv',config.ID,validationYear)),QuoteStrings=true);
fprintf('%s year %d: RMSE %.5f; MAE %.5f; %.1fs; %d iterations; %s\n', ...
    config.ID,validationYear,record.RMSE,record.MAE,trainingSeconds, ...
    record.Iterations,record.Termination);
end
