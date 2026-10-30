function summary = wids_local_summary(records, configs)
%WIDS_LOCAL_SUMMARY Rank only configurations with both successful folds.
summary = table;
for configIndex = 1:height(configs)
    folds = records(configIndex,:);
    successful = cellfun(@(x) ~isempty(x) && strcmp(x.Status,'ok'),folds);
    if ~all(successful)
        continue
    end
    validationYears = cellfun(@(x) x.ValidationYear,folds);
    if ~isequal(sort(validationYears),[4,5])
        error('WiDS:IncompleteFolds','Expected exactly validation years 4 and 5.');
    end
    totalRows = sum(cellfun(@(x) x.ValidationRows,folds));
    pooledRMSE = sqrt(sum(cellfun(@(x) x.SSE,folds))/totalRows);
    pooledMAE = sum(cellfun(@(x) x.SAE,folds))/totalRows;
    row = [configs(configIndex,:),table(pooledRMSE,pooledMAE, ...
        folds{1}.RMSE,folds{2}.RMSE,totalRows, ...
        sum(cellfun(@(x) x.TrainingSeconds,folds)), ...
        'VariableNames',{'PooledRMSE','PooledMAE','Year4RMSE','Year5RMSE', ...
        'ValidationRows','TrainingSeconds'})];
    summary = [summary;row]; %#ok<AGROW>
end
if ~isempty(summary)
    summary = sortrows(summary,{'PooledRMSE','PooledMAE'});
end
end
