function summary = main()
%MAIN Run the five stages for the selected full-data MATLAB solution.
% Put train.csv, test.csv and sample_solution.csv in data/ or set WIDS_DATA_DIR.
% Original local timings: residual 62s, boost 70s, forest 31s (about 2.7 min
% fitting total). Allow roughly 2-8 min including preparation/export on a
% comparable computer. MATLAB Online and other hardware can take longer.
% Matching checkpoints are reused; this function does not submit to Kaggle.
setup_wids_project;
root=fileparts(mfilename('fullpath'));previous=pwd;
restore=onCleanup(@()cd(previous));cd(fullfile(root,'kaggle_submission'));
stages=["prepare","residual","boost","forest","export"];
seconds=zeros(numel(stages),1);timerAll=tic;
fprintf('Five-stage local MATLAB run. Typical estimate: 2-8 min; hardware dependent.\n');
for index=1:numel(stages)
    fprintf('Stage %d/5: %s\n',index,stages(index));timer=tic;
    run_wids_submission(stages(index));seconds(index)=toc(timer);
    fprintf('Finished %s in %.1f seconds.\n',stages(index),seconds(index));
end
summary=table(stages',seconds,'VariableNames',{'Stage','Seconds'});
writetable(summary,'runtime_summary.csv');
fprintf('All stages completed in %.1f seconds.\n',toc(timerAll));disp(summary);
end
