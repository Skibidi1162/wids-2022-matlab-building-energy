function setup_wids_project()
%SETUP_WIDS_PROJECT Add project workflows to the MATLAB path.
root = fileparts(mfilename('fullpath'));
addpath(root,fullfile(root,'kaggle_submission'),fullfile(root,'local_tuning'), ...
    fullfile(root,'local_model_comparison'),fullfile(root,'model_comparison_charts'));
fprintf('WiDS MATLAB project ready. Data directory: %s\n',wids_data_dir());
end
