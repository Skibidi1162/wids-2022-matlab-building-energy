function summary = evaluate_wids_blends()
%EVALUATE_WIDS_BLENDS Score three preset boost/forest prediction averages.
folder=fileparts(mfilename('fullpath'));
resultDir=fullfile(folder,'results');
signature=wids_model_signature();
raw=readtable(signature.DataFile);
configs=wids_model_configs();
forestConfig=configs(string({configs.ID})=="RF100");
assert(isscalar(forestConfig));
forestWeights=[0.25,0.5,0.75];
summary=table('Size',[0,6], ...
    'VariableTypes',{'string','double','double','double','double','double'}, ...
    'VariableNames',{'ConfigID','ForestWeight','PooledRMSE','PooledMAE', ...
    'Year4RMSE','Year5RMSE'});
for index=1:numel(forestWeights)
    forestWeight=forestWeights(index);
    configID=sprintf('BLEND_RF%03d',round(100*forestWeight));
    sse=zeros(1,2);sae=sse;n=sse;foldRMSE=sse;
    for fold=1:2
        year=fold+3;
        boost=verifiedBoostFold(folder,signature,raw,year);
        forest=load(fullfile(resultDir,sprintf('RF100_year%d.mat',year)));
        expectedForestKey=struct('Signature',signature,'Config',forestConfig, ...
            'ValidationYear',year,'Seed',42);
        assert(isequaln(forest.record.Key,expectedForestKey));
        assert(strcmp(forest.record.Status,'ok') && string(forest.record.ConfigID)=="RF100");
        assert(forest.record.ValidationYear==year);
        target=raw(raw.Year_Factor==year,:);
        assert(isequal(forest.validationIDs,target.id));
        assert(forest.record.FitRows==sum(raw.Year_Factor<year));
        assert(forest.record.ValidationRows==height(target));
        assert(isequal(size(forest.predictions),size(target.site_eui)));
        assert(all(isfinite(forest.predictions)));
        forestResidual=forest.predictions-target.site_eui;
        forestSSE=sum(forestResidual.^2);forestSAE=sum(abs(forestResidual));
        assert(abs(forestSSE-forest.record.SSE)<=1e-12*max(1,abs(forestSSE)));
        assert(abs(forestSAE-forest.record.SAE)<=1e-12*max(1,abs(forestSAE)));
        assert(abs(sqrt(forestSSE/height(target))-forest.record.RMSE)<1e-9);
        assert(abs(forestSAE/height(target)-forest.record.MAE)<1e-9);
        predictions=(1-forestWeight)*boost.predictions+forestWeight*forest.predictions;
        assert(all(isfinite(predictions)) && isequal(size(predictions),size(target.site_eui)));
        residual=predictions-target.site_eui;
        sse(fold)=sum(residual.^2);sae(fold)=sum(abs(residual));n(fold)=height(target);
        foldRMSE(fold)=sqrt(sse(fold)/n(fold));
        validationIDs=target.id;
        record=struct('ConfigID',configID,'ForestWeight',forestWeight, ...
            'ValidationYear',year,'ValidationRows',n(fold),'SSE',sse(fold),'SAE',sae(fold), ...
            'RMSE',foldRMSE(fold),'MAE',sae(fold)/n(fold),'Status','ok', ...
            'BaseConfigIDs',{{'L07','RF100'}},'BaseKeys',{{boost.record.Key,forest.record.Key}});
        save(fullfile(resultDir,sprintf('%s_year%d.mat',configID,year)), ...
            'record','validationIDs','predictions','-v7');
    end
    summary(end+1,:)={string(configID),forestWeight,sqrt(sum(sse)/sum(n)), ...
        sum(sae)/sum(n),foldRMSE(1),foldRMSE(2)}; %#ok<AGROW>
end
summary=sortrows(summary,{'PooledRMSE','PooledMAE'});
writetable(summary,fullfile(resultDir,'blend_comparison_results.csv'));
disp(summary);
fprintf('Blend weights were compared using the historical model-selection folds.\n');
end

function boost = verifiedBoostFold(folder,signature,raw,year)
% Match the archived signature shape used by the original tuning runner.
boostFolder=fullfile(folder,'..','local_tuning');
boost=load(fullfile(boostFolder,'results',sprintf('L07_year%d.mat',year)));
expectedSignature=struct('DataSHA256',signature.DataSHA256, ...
    'MATLABVersion',signature.MATLABVersion, ...
    'RunnerSource',fileread(fullfile(boostFolder,'run_local_tuning.m')), ...
    'CleaningSource',fileread(fullfile(boostFolder,'wids_clean_split.m')), ...
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
