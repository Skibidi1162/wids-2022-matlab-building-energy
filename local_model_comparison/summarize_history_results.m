function summary = summarize_history_results()
%SUMMARIZE_HISTORY_RESULTS Verify full-fold and history-group prediction scores.
folder=fileparts(mfilename('fullpath'));resultDir=fullfile(folder,'results');
signature=wids_model_signature();raw=readtable(signature.DataFile);
methods=["HISTORY_LATEST","HISTORY_DIRECT","HISTORY_RESIDUAL"];
folds=cell(1,2);
for fold=1:2
    year=fold+3;
    saved=load(fullfile(resultDir,sprintf('HISTORY_year%d.mat',year)));
    fallback=wids_verified_history_fallback(folder,signature,raw,year);
    expected=struct('Signature',signature,'ValidationYear',year,'Seed',42, ...
        'RunnerSource',fileread(fullfile(folder,'run_building_history_case.m')), ...
        'HistorySource',fileread(fullfile(folder,'wids_past_building_features.m')), ...
        'FallbackSource',fileread(fullfile(folder,'wids_verified_history_fallback.m')), ...
        'FallbackBaseKeys',{fallback.record.BaseKeys},'FallbackForestWeight',0.5);
    assert(isequaln(saved.key,expected));
    target=raw(raw.Year_Factor==year,:);
    assert(isequal(saved.validationIDs,target.id));
    assert(isequal(saved.actual,target.site_eui));
    assert(isequal(saved.fallbackPredictions,fallback.predictions));
    assert(numel(saved.hasHistory)==height(target));
    for method=methods
        prediction=saved.predictions.(method);
        assert(isequal(size(prediction),size(target.site_eui)) && all(isfinite(prediction)));
        row=saved.records(saved.records.Method==method,:);assert(height(row)==1);
        residual=prediction-target.site_eui;
        assert(abs(sum(residual.^2)-row.SSE)<=1e-12*max(1,row.SSE));
        assert(abs(sum(abs(residual))-row.SAE)<=1e-12*max(1,row.SAE));
        assert(row.ValidationRows==height(target));
        assert(row.HistoryRows==sum(saved.hasHistory));
        assert(abs(sqrt(mean(residual.^2))-row.RMSE)<1e-9);
        assert(abs(mean(abs(residual))-row.MAE)<1e-9);
        expectedHistory=sqrt(mean(residual(saved.hasHistory).^2));
        expectedNoHistory=sqrt(mean(residual(~saved.hasHistory).^2));
        assert(isequaln(expectedHistory,row.HistoryRMSE) || abs(expectedHistory-row.HistoryRMSE)<1e-9);
        assert(isequaln(expectedNoHistory,row.NoHistoryRMSE) || abs(expectedNoHistory-row.NoHistoryRMSE)<1e-9);
    end
    folds{fold}=saved;
end
summary=table;
for method=methods
    rows=[folds{1}.records(folds{1}.records.Method==method,:); ...
        folds{2}.records(folds{2}.records.Method==method,:)];
    residual=[folds{1}.predictions.(method)-folds{1}.actual; ...
        folds{2}.predictions.(method)-folds{2}.actual];
    history=[folds{1}.hasHistory;folds{2}.hasHistory];
    row=table(method,sqrt(mean(residual.^2)),mean(abs(residual)),rows.RMSE(1),rows.RMSE(2), ...
        sqrt(mean(residual(history).^2)),sqrt(mean(residual(~history).^2)), ...
        sum(history),sum(~history),sum(rows.TrainingSeconds), ...
        'VariableNames',{'Method','PooledRMSE','PooledMAE','Year4RMSE','Year5RMSE', ...
        'HistoryRMSE','NoHistoryRMSE','HistoryRows','NoHistoryRows','TrainingSeconds'});
    summary=[summary;row]; %#ok<AGROW>
end
baselineResidual=[folds{1}.fallbackPredictions-folds{1}.actual; ...
    folds{2}.fallbackPredictions-folds{2}.actual];
baselineRMSE=sqrt(mean(baselineResidual.^2));
summary.RMSEChangeVsBlend=summary.PooledRMSE-baselineRMSE;
summary=sortrows(summary,{'PooledRMSE','PooledMAE'});
writetable(summary,fullfile(resultDir,'history_comparison_results.csv'));
disp(summary);
fprintf('Verified six history prediction vectors against original labels.\n');
end
