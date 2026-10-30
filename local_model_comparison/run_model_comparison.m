%% Run or resume the five initial alternatives, with two historical folds
widsOtherFolder=fileparts(mfilename('fullpath'));
widsOtherConfigs=wids_model_configs();
for widsOtherIndex=1:numel(widsOtherConfigs)
    for widsOtherYear=[4,5]
        wids_run_model_case(widsOtherConfigs(widsOtherIndex).ID,widsOtherYear);
    end
end
widsOtherModelResults=wids_model_summary(fullfile(widsOtherFolder,'results'));
disp(widsOtherModelResults);
