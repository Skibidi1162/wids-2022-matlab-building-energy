function summary = wids_model_summary(resultDir,signature)
%WIDS_MODEL_SUMMARY Aggregate only matching cases with both successful folds.
if nargin<2
    signature=wids_model_signature();
end
configs=wids_model_configs();
summary=table('Size',[0,7], ...
    'VariableTypes',{'string','string','double','double','double','double','double'}, ...
    'VariableNames',{'ConfigID','Family','PooledRMSE','PooledMAE', ...
    'Year4RMSE','Year5RMSE','TrainingSeconds'});
for index=1:numel(configs)
    records=cell(1,2);
    for fold=1:2
        year=fold+3;
        file=fullfile(resultDir,sprintf('%s_year%d.mat',configs(index).ID,year));
        expected=struct('Signature',signature,'Config',configs(index),'ValidationYear',year,'Seed',42);
        if isfile(file)
            saved=load(file,'record');
            if isequaln(saved.record.Key,expected) && strcmp(saved.record.Status,'ok')
                records{fold}=saved.record;
            end
        end
    end
    if any(cellfun(@isempty,records)),continue,end
    n=sum(cellfun(@(x)x.ValidationRows,records));
    row=table(configs(index).ID,configs(index).Family, ...
        sqrt(sum(cellfun(@(x)x.SSE,records))/n), ...
        sum(cellfun(@(x)x.SAE,records))/n,records{1}.RMSE,records{2}.RMSE, ...
        sum(cellfun(@(x)x.TrainingSeconds,records)), ...
        'VariableNames',summary.Properties.VariableNames);
    summary=[summary;row]; %#ok<AGROW>
end
if ~isempty(summary),summary=sortrows(summary,{'PooledRMSE','PooledMAE'});end
writetable(summary,fullfile(resultDir,'model_comparison_results.csv'));
end
