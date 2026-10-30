function comparison = verify_model_comparison()
%VERIFY_MODEL_COMPARISON Recompute scores from saved predictions and raw labels.
folder=fileparts(mfilename('fullpath'));
resultDir=fullfile(folder,'results');
signature=wids_model_signature();
raw=readtable(signature.DataFile);
configs=wids_model_configs();
verification=table('Size',[0,7], ...
    'VariableTypes',{'string','double','double','double','double','double','double'}, ...
    'VariableNames',{'ConfigID','ValidationYear','FitRows','ValidationRows', ...
    'EncodedPredictors','VerifiedRMSE','VerifiedMAE'});
diagnosticText="";
for index=1:numel(configs)
    for year=[4,5]
        saved=load(fullfile(resultDir,sprintf('%s_year%d.mat',configs(index).ID,year)));
        expected=struct('Signature',signature,'Config',configs(index), ...
            'ValidationYear',year,'Seed',42);
        assert(isequaln(saved.record.Key,expected));
        assert(strcmp(saved.record.Status,'ok'));
        target=raw(raw.Year_Factor==year,:);
        assert(isequal(saved.validationIDs,target.id));
        assert(saved.record.FitRows==sum(raw.Year_Factor<year));
        assert(saved.record.ValidationRows==height(target));
        assert(isequal(size(saved.predictions),size(target.site_eui)));
        assert(all(isfinite(saved.predictions)));
        residual=saved.predictions-target.site_eui;
        sse=sum(residual.^2);sae=sum(abs(residual));
        rmse=sqrt(sse/height(target)); mae=sae/height(target);
        assert(abs(sse-saved.record.SSE)<=1e-12*max(1,abs(sse)));
        assert(abs(sae-saved.record.SAE)<=1e-12*max(1,abs(sae)));
        assert(abs(rmse-saved.record.RMSE)<1e-9);
        assert(abs(mae-saved.record.MAE)<1e-9);
        width=59;
        if isfield(saved.encoding,'Columns'),width=numel(saved.encoding.Columns);end
        verification(end+1,:)={configs(index).ID,year,saved.record.FitRows, ...
            height(target),width,rmse,mae}; %#ok<AGROW>
        diagnosticText=diagnosticText+sprintf('\n%s year %d\n',configs(index).ID,year);
        diagnosticText=diagnosticText+string(evalc('disp(saved.diagnostics)'));
        if isfield(saved.diagnostics,'ConvergenceInfo')
            diagnosticText=diagnosticText+string(evalc('disp(saved.diagnostics.ConvergenceInfo)'));
        end
        if isfield(saved.diagnostics,'FitInfo')
            diagnosticText=diagnosticText+string(evalc('disp(saved.diagnostics.FitInfo)'));
        end
    end
end
% The follow-up has its own runner provenance and does not change base keys.
longerConfig=configs(string({configs.ID})=="NET64x32");
assert(isscalar(longerConfig));
longerConfig.ID="NET64x32_1000";longerConfig.Parameters.IterationLimit=1000;
longerRecords=cell(1,2);
for fold=1:2
    year=fold+3;
    file=fullfile(resultDir,sprintf('%s_year%d.mat',longerConfig.ID,year));
    if ~isfile(file),continue,end
    saved=load(file);
    expected=struct('Signature',signature,'Config',longerConfig, ...
        'ValidationYear',year,'Seed',42, ...
        'RunnerSource',fileread(fullfile(folder,'run_longer_network_case.m')));
    assert(isequaln(saved.record.Key,expected));
    assert(strcmp(saved.record.Status,'ok') && string(saved.record.ConfigID)==longerConfig.ID);
    assert(saved.record.ValidationYear==year);
    target=raw(raw.Year_Factor==year,:);
    assert(isequal(saved.validationIDs,target.id));
    assert(saved.record.FitRows==sum(raw.Year_Factor<year));
    assert(saved.record.ValidationRows==height(target));
    assert(isequal(size(saved.predictions),size(target.site_eui)));
    assert(all(isfinite(saved.predictions)));
    residual=saved.predictions-target.site_eui;
    sse=sum(residual.^2);sae=sum(abs(residual));
    rmse=sqrt(sse/height(target));mae=sae/height(target);
    assert(abs(sse-saved.record.SSE)<=1e-12*max(1,abs(sse)));
    assert(abs(sae-saved.record.SAE)<=1e-12*max(1,abs(sae)));
    assert(abs(rmse-saved.record.RMSE)<1e-9);
    assert(abs(mae-saved.record.MAE)<1e-9);
    verification(end+1,:)={longerConfig.ID,year,saved.record.FitRows, ...
        height(target),numel(saved.encoding.Columns),rmse,mae}; %#ok<AGROW>
    longerRecords{fold}=saved.record;
    diagnosticText=diagnosticText+sprintf('\n%s year %d\n',longerConfig.ID,year);
    diagnosticText=diagnosticText+string(evalc('disp(saved.diagnostics)'));
    diagnosticText=diagnosticText+string(evalc('disp(saved.diagnostics.ConvergenceInfo)'));
end
candidates=wids_model_summary(resultDir,signature);
assert(height(candidates)==numel(configs));
if all(~cellfun(@isempty,longerRecords))
    n=sum(cellfun(@(x)x.ValidationRows,longerRecords));
    row=table(longerConfig.ID,longerConfig.Family, ...
        sqrt(sum(cellfun(@(x)x.SSE,longerRecords))/n), ...
        sum(cellfun(@(x)x.SAE,longerRecords))/n, ...
        longerRecords{1}.RMSE,longerRecords{2}.RMSE, ...
        sum(cellfun(@(x)x.TrainingSeconds,longerRecords)), ...
        'VariableNames',candidates.Properties.VariableNames);
    candidates=[candidates;row];
end
boostSSE=zeros(1,2);boostSAE=boostSSE;boostN=boostSSE;
boostRMSE=boostSSE;boostSeconds=boostSSE;
for fold=1:2
    year=fold+3;
    boost=verifiedBoostFold(folder,signature,raw,year);
    target=raw(raw.Year_Factor==year,:);
    residual=boost.predictions-target.site_eui;
    boostSSE(fold)=sum(residual.^2);boostSAE(fold)=sum(abs(residual));
    boostN(fold)=height(target);boostRMSE(fold)=sqrt(boostSSE(fold)/boostN(fold));
    boostSeconds(fold)=boost.record.TrainingSeconds;
    verification(end+1,:)={"L07",year,boost.record.FitRows,boostN(fold), ...
        numel(signature.PredictorNames),boostRMSE(fold),boostSAE(fold)/boostN(fold)}; %#ok<AGROW>
end
writetable(verification,fullfile(resultDir,'verified_prediction_metrics.csv'));
fid=fopen(fullfile(resultDir,'solver_diagnostics.txt'),'w');
assert(fid>=0);closeFile=onCleanup(@()fclose(fid));
fprintf(fid,'%s',diagnosticText);
referenceRMSE=sqrt(sum(boostSSE)/sum(boostN));
row=table("L07","boosted",referenceRMSE,sum(boostSAE)/sum(boostN), ...
    boostRMSE(1),boostRMSE(2),sum(boostSeconds), ...
    'VariableNames',candidates.Properties.VariableNames);
comparison=[row;candidates];
comparison.RMSEChangeVsL07=comparison.PooledRMSE-referenceRMSE;
comparison=sortrows(comparison,{'PooledRMSE','PooledMAE'});
writetable(comparison,fullfile(resultDir,'comparison_with_boosted_reference.csv'));
disp(comparison);
fprintf('Verified all %d saved prediction vectors against original labels.\n',height(verification));
end

function boost = verifiedBoostFold(folder,signature,raw,year)
% The original tuning runner archived a different signature structure.
boostFolder=fullfile(folder,'..','local_tuning');
boost=load(fullfile(boostFolder,'results',sprintf('L07_year%d.mat',year)));
expectedSignature=struct('DataSHA256',signature.DataSHA256, ...
    'MATLABVersion',signature.MATLABVersion, ...
    'RunnerSource',fileread(fullfile(boostFolder,'run_local_tuning.m')), ...
    'CleaningSource',fileread(wids_shared_file("wids_clean_split.m")), ...
    'SummarySource',fileread(fullfile(boostFolder,'wids_local_summary.m')), ...
    'PredictorNames',{signature.PredictorNames});
cleaningField=matlab.lang.makeValidName('wids_clean_split.m');
assert(strcmp(expectedSignature.CleaningSource,signature.Sources.(cleaningField)), ...
    'WiDS:ReferenceCleaning','Boosted reference and alternatives must use identical cleaning.');
expectedConfig=struct('ConfigID',"L07",'Description',"Smaller leaves", ...
    'Trees',300,'LearnRate',0.05,'MaxNumSplits',31,'MinLeafSize',5);
expectedKey=struct('Signature',expectedSignature,'Config',expectedConfig, ...
    'ValidationYear',year,'Seed',42);
assert(isequaln(boost.record.Key,expectedKey), ...
    'WiDS:ReferenceProvenance','L07 checkpoint does not match the expected data, code, predictors, configuration, and fold.');
assert(strcmp(boost.record.Status,'ok') && string(boost.record.ConfigID)=="L07");
assert(boost.record.ValidationYear==year);
target=raw(raw.Year_Factor==year,:);
assert(isequal(boost.validationIDs,target.id));
assert(boost.record.FitRows==sum(raw.Year_Factor<year));
assert(boost.record.ValidationRows==height(target));
assert(isequal(size(boost.predictions),size(target.site_eui)));
assert(all(isfinite(boost.predictions)));
residual=boost.predictions-target.site_eui;
sse=sum(residual.^2);sae=sum(abs(residual));
assert(abs(sse-boost.record.SSE)<=1e-12*max(1,abs(sse)));
assert(abs(sae-boost.record.SAE)<=1e-12*max(1,abs(sae)));
assert(abs(sqrt(sse/height(target))-boost.record.RMSE)<1e-9);
assert(abs(sae/height(target)-boost.record.MAE)<1e-9);
end
