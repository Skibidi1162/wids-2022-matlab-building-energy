function fallback = wids_verified_history_fallback(folder,signature,raw,year)
%WIDS_VERIFIED_HISTORY_FALLBACK Verify the archived 50:50 boost/forest blend.
% Read-only verification of both base checkpoints, their complete provenance,
% the blend's base keys, row alignment, prediction formula, and saved metrics.
arguments
    folder (1,1) string
    signature (1,1) struct
    raw table
    year (1,1) double {mustBeMember(year,[4,5])}
end
resultDir=fullfile(folder,'results');
target=raw(raw.Year_Factor==year,:);
assert(height(target)>0 && all(isfinite(target.site_eui)), ...
    'WiDS:FallbackTargets','The validation fold must have finite responses.');
fitRows=sum(raw.Year_Factor<year);

% L07 was completed before later tuning-runner fixes. Reconstruct its exact
% archived signature shape from the current published sources used to regenerate checkpoints.
boostFolder=fullfile(folder,'..','local_tuning');
provenanceFolder=boostFolder;
boost=load(fullfile(boostFolder,'results',sprintf('L07_year%d.mat',year)), ...
    'record','validationIDs','predictions');
boostSignature=struct('DataSHA256',signature.DataSHA256, ...
    'MATLABVersion',signature.MATLABVersion, ...
    'RunnerSource',fileread(fullfile(provenanceFolder,'run_local_tuning.m')), ...
    'CleaningSource',fileread(wids_shared_file("wids_clean_split.m")), ...
    'SummarySource',fileread(fullfile(provenanceFolder,'wids_local_summary.m')), ...
    'PredictorNames',{signature.PredictorNames});
cleaningField=matlab.lang.makeValidName('wids_clean_split.m');
assert(strcmp(boostSignature.CleaningSource,signature.Sources.(cleaningField)), ...
    'WiDS:FallbackCleaning','L07 and the current models must use identical cleaning.');
boostConfig=struct('ConfigID',"L07",'Description',"Smaller leaves", ...
    'Trees',300,'LearnRate',0.05,'MaxNumSplits',31,'MinLeafSize',5);
boostKey=struct('Signature',boostSignature,'Config',boostConfig, ...
    'ValidationYear',year,'Seed',42);
assert(isequaln(boost.record.Key,boostKey), ...
    'WiDS:FallbackBoostProvenance','L07 does not match its expected archived provenance.');
verifyPrediction(boost,target,year,"L07");
assert(boost.record.FitRows==fitRows);

configs=wids_model_configs();
forestConfig=configs(string({configs.ID})=="RF100");
assert(isscalar(forestConfig));
forest=load(fullfile(resultDir,sprintf('RF100_year%d.mat',year)), ...
    'record','validationIDs','predictions');
forestKey=struct('Signature',signature,'Config',forestConfig, ...
    'ValidationYear',year,'Seed',42);
assert(isequaln(forest.record.Key,forestKey), ...
    'WiDS:FallbackForestProvenance','RF100 does not match its expected current provenance.');
verifyPrediction(forest,target,year,"RF100");
assert(forest.record.FitRows==fitRows);

fallback=load(fullfile(resultDir,sprintf('BLEND_RF050_year%d.mat',year)));
assert(fallback.record.ForestWeight==0.5, ...
    'WiDS:FallbackWeight','The history fallback must use a 50:50 blend.');
assert(isequal(fallback.record.BaseConfigIDs,{'L07','RF100'}), ...
    'WiDS:FallbackBaseIDs','The fallback base model IDs or their order differ.');
assert(isequaln(fallback.record.BaseKeys,{boost.record.Key,forest.record.Key}), ...
    'WiDS:FallbackBaseProvenance','The blend base keys differ from the verified checkpoints.');
verifyPrediction(fallback,target,year,"BLEND_RF050");
expectedPredictions=0.5*boost.predictions+0.5*forest.predictions;
assert(isequal(fallback.predictions,expectedPredictions), ...
    'WiDS:FallbackPredictions','The saved fallback is not the exact verified 50:50 blend.');
end

function verifyPrediction(saved,target,year,configID)
assert(strcmp(saved.record.Status,'ok') && string(saved.record.ConfigID)==configID, ...
    'WiDS:FallbackStatus','A fallback component is unsuccessful or mislabeled.');
assert(saved.record.ValidationYear==year);
assert(saved.record.ValidationRows==height(target));
assert(isequal(saved.validationIDs,target.id));
assert(isequal(size(saved.predictions),size(target.site_eui)));
assert(all(isfinite(saved.predictions)));
residual=saved.predictions-target.site_eui;
sse=sum(residual.^2);sae=sum(abs(residual));
assert(isfinite(sse) && isfinite(sae));
assert(abs(sse-saved.record.SSE)<=1e-12*max(1,abs(sse)));
assert(abs(sae-saved.record.SAE)<=1e-12*max(1,abs(sae)));
assert(abs(sqrt(sse/height(target))-saved.record.RMSE)<1e-9);
assert(abs(sae/height(target)-saved.record.MAE)<1e-9);
end
