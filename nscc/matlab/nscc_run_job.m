function nscc_run_job
%NSCC_RUN_JOB One configuration and one temporal fold per scheduler job.
% Restarts reuse prepared/model checkpoints; interrupted fitting restarts.
root = nscc_util('root');
addpath(fullfile(root,'reference'));
runRoot = nscc_util('runroot');
context = nscc_util('context');
maxNumCompThreads(context.Threads); %#ok<MAXNCT>
probe = nscc_util('readjson',fullfile(runRoot,'probe.json'));
assert(probe.Ready && isequaln(context,probe.Context), ...
    'WiDS:Probe','A successful matching probe is required for this run.');
jobs = nscc_util('readjson',fullfile(root,'manifests','jobs.json'));
jobID = str2double(getenv('WIDS_JOB_ID'));
assert(isfinite(jobID) && jobID==fix(jobID) && jobID>=1 && jobID<=numel(jobs), ...
    'WiDS:Job','Invalid WIDS_JOB_ID.');
job = jobs(jobID);
assert(job.JobID==jobID,'WiDS:Job','Manifest job index mismatch.');
configs = nscc_util('readjson',fullfile(root,'manifests','configurations.json'));
config = configs(strcmp({configs.ID},job.ConfigID));
assert(isscalar(config),'WiDS:Config','Configuration ID must be unique.');
identity = struct('Context',context,'Job',job,'Config',config);
jobDir = fullfile(runRoot,'jobs',sprintf('job_%04d',jobID));
if ~isfolder(jobDir), mkdir(jobDir); end
% Atomic mkdir in Java avoids two scheduler jobs writing one checkpoint.
lockPath = fullfile(jobDir,'running.lock');
lockObject = java.io.File(lockPath);
assert(lockObject.mkdir(),'WiDS:Lock', ...
    'Job lock exists: %s. Check qstat before recovering a stale lock.',lockPath);
lockCleanup = onCleanup(@() rmdir(lockPath)); %#ok<NASGU>
diary(fullfile(jobDir,'matlab.log'));
diaryCleanup = onCleanup(@() diary('off')); %#ok<NASGU>
try
    finishedPath = fullfile(jobDir,'result.mat');
    if isfile(finishedPath)
        result = nscc_util('loadmat',finishedPath);
        assert(isequaln(result.Identity,identity),'WiDS:Resume','Identity mismatch.');
        if isfile(fullfile(jobDir,'result.json')) && ...
                isfile(fullfile(jobDir,'predictions.csv'))
            summary = nscc_util('readjson',fullfile(jobDir,'result.json'));
            assert(strcmp(summary.PredictionsSHA256, ...
                nscc_util('sha256',fullfile(jobDir,'predictions.csv'))), ...
                'WiDS:Resume','Prediction checksum mismatch.');
            fprintf('Job %d already complete; preserving results.\n',jobID);
            return
        end
    end
    preparedPath = fullfile(jobDir,'prepared.mat');
    if isfile(preparedPath)
        prepared = nscc_util('loadmat',preparedPath);
        assert(isequaln(prepared.Identity,identity), ...
            'WiDS:Resume','Prepared checkpoint identity mismatch.');
    else
        t = tic;
        prepared = nscc_prepare(job.FoldIndex,config.Family);
        prepared.PrepareSeconds = toc(t);
        prepared.Identity = identity;
        nscc_util('savemat',preparedPath,prepared);
    end
    state = struct('Identity',identity,'Phase','prepared', ...
        'UpdatedUTC',nscc_util('timestamp'));
    nscc_util('writejson',fullfile(jobDir,'state.json'),state);
    modelPath = fullfile(jobDir,'model.mat');
    if isfile(modelPath)
        fitted = nscc_util('loadmat',modelPath);
        assert(isequaln(fitted.Identity,identity), ...
            'WiDS:Resume','Model checkpoint identity mismatch.');
    else
        state.Phase = 'training'; state.UpdatedUTC = nscc_util('timestamp');
        nscc_util('writejson',fullfile(jobDir,'state.json'),state);
        t = tic;
        [model,diagnostics] = nscc_fit(config,prepared.Xfit, ...
            prepared.Yfit,job.Seed);
        fitted = struct('Identity',identity,'Model',model, ...
            'Diagnostics',diagnostics,'FitSeconds',toc(t),'RNGAfterFit',rng);
        nscc_util('savemat',modelPath,fitted);
    end
    state.Phase = 'predicting'; state.UpdatedUTC = nscc_util('timestamp');
    nscc_util('writejson',fullfile(jobDir,'state.json'),state);
    t = tic;
    yhat = double(predict(fitted.Model,prepared.Xval));
    predictSeconds = toc(t);
    assert(iscolumn(yhat) && numel(yhat)==prepared.Fold.ValidationN && ...
        all(isfinite(yhat)),'WiDS:Prediction','Invalid predictions.');
    % No target scaling, log transformation, clipping, or post-processing.
    residual = yhat - prepared.Yval;
    summary = struct('Status','complete','Identity',identity, ...
        'NFit',numel(prepared.Yfit),'N',numel(residual), ...
        'SSE',sum(residual.^2),'SAE',sum(abs(residual)), ...
        'RMSE',sqrt(mean(residual.^2)),'MAE',mean(abs(residual)), ...
        'PrepareSeconds',prepared.PrepareSeconds,'FitSeconds',fitted.FitSeconds, ...
        'PredictSeconds',predictSeconds,'EncodedP',prepared.EncodedP, ...
        'ValidationUnknownCounts',prepared.ValidationUnknownCounts, ...
        'CompletedUTC',nscc_util('timestamp'),'PBSJobID',getenv('PBS_JOBID'));
    summary.DiagnosticsText = evalc('disp(fitted.Diagnostics)');
    if strcmp(config.Family,'net')
        summary.DiagnosticsText = evalc('disp(fitted.Diagnostics.ConvergenceInfo)');
    end
    predictions = table(prepared.ValidationIDs,prepared.Yval,yhat, ...
        'VariableNames',{'id','site_eui','prediction'});
    tmp = fullfile(jobDir,'predictions.tmp.csv');
    writetable(predictions,tmp);
    [ok,msg] = movefile(tmp,fullfile(jobDir,'predictions.csv'),'f');
    assert(ok,'WiDS:IO','%s',msg);
    summary.PredictionsSHA256 = nscc_util('sha256',fullfile(jobDir,'predictions.csv'));
    result = struct('Identity',identity,'Summary',summary, ...
        'Predictions',predictions,'Cleaning',prepared.Cleaning, ...
        'Encoding',prepared.Encoding,'Diagnostics',fitted.Diagnostics);
    nscc_util('savemat',finishedPath,result);
    % Completion marker written last. Aggregation never accepts partial output.
    nscc_util('writejson',fullfile(jobDir,'result.json'),summary);
    state.Phase = 'complete'; state.UpdatedUTC = nscc_util('timestamp');
    nscc_util('writejson',fullfile(jobDir,'state.json'),state);
    fprintf('Job %d complete: N=%d RMSE=%.8f MAE=%.8f\n', ...
        jobID,summary.N,summary.RMSE,summary.MAE);
catch err
    failure = struct('Status','failed','Identity',identity, ...
        'FailedUTC',nscc_util('timestamp'),'Identifier',err.identifier, ...
        'Message',err.message,'Report',getReport(err,'extended','hyperlinks','off'));
    nscc_util('writejson',fullfile(jobDir,'failure.json'),failure);
    rethrow(err)
end
end
