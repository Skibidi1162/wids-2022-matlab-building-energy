function nscc_probe
%NSCC_PROBE Compute-node environment/licence probe plus tiny CPU smoke fits.
root = nscc_util('root'); addpath(fullfile(root,'reference'));
runRoot = nscc_util('runroot');
context = nscc_util('context');
maxNumCompThreads(context.Threads); %#ok<MAXNCT>
path = fullfile(runRoot,'probe.json');
if isfile(path)
    old = nscc_util('readjson',path);
    assert(isequaln(old.Context,context),'WiDS:Probe', ...
        'Existing run context differs. Use a new run tag.');
    if old.Ready, fprintf('Matching successful probe already exists.\n'); return; end
end
report = struct('Ready',false,'Context',context, ...
    'TimestampUTC',nscc_util('timestamp'),'PBSJobID',getenv('PBS_JOBID'), ...
    'MATLABRoot',matlabroot,'Toolboxes',ver, ...
    'StatisticsLicenseTest',logical(license('test','Statistics_Toolbox')), ...
    'ParallelLicenseTest',logical(license('test','Distrib_Computing_Toolbox')), ...
    'DeepLearningLicenseTest',logical(license('test','Neural_Network_Toolbox')));
report.Capabilities = struct;
for name = ["fitrensemble","fitrkernel","fitrnet","fitrlinear"]
    report.Capabilities.(name) = which(name);
end
report.Errors = {};
if verLessThan('matlab','23.2')
    report.Errors{end+1} = 'Package requires full MATLAB R2023b or newer.';
end
try
    nscc_selftest;
    % Real historical data: check counts and fitting preprocessing, no model fit.
    a = nscc_prepare(1,'linear'); b = nscc_prepare(2,'linear');
    report.FoldChecks = [a.Fold;b.Fold];
    clear a b
catch err
    report.Errors{end+1} = getReport(err,'extended','hyperlinks','off');
end
configs = nscc_util('readjson',fullfile(root,'manifests','configurations.json'));
rng(71,'twister');
X = randn(80,5); y = 4*X(:,1)-2*X(:,2)+randn(80,1);
for family = ["linear","forest","kernel","net"]
    key = char(family);
    try
        c = configs(find(strcmp({configs.Family},key),1));
        if family=="forest"
            c.Parameters.Trees = 5; c.Parameters.MinLeafSize=4;
            c.Parameters.MaxNumSplits=15; c.Parameters.Mtry=3;
            T = array2table(X,'VariableNames', ...
                {'x1','x2','State_Factor','building_class','facility_type'});
            for name = ["State_Factor","building_class","facility_type"]
                T.(name) = addcats(categorical(T.(name)>0),{'__unknown__'});
            end
            [model,~] = nscc_fit(c,T,y,71);
            test = T(1:4,:);
            % Include an unobserved reserved level, as in real temporal folds.
            test.facility_type(1) = '__unknown__';
        else
            if family=="kernel", c.Parameters.ExpansionDimensions=32; end
            c.Parameters.IterationLimit=30;
            [model,~] = nscc_fit(c,X,y,71);
            test = X(1:4,:);
        end
        pred = predict(model,test);
        assert(all(isfinite(pred)),'WiDS:Smoke','Nonfinite smoke predictions.');
        report.Smoke.(key) = struct('Passed',true,'Message','Tiny CPU fit and prediction passed');
    catch err
        report.Smoke.(key) = struct('Passed',false,'Message',err.message);
        report.Errors{end+1} = sprintf('%s: %s',key,err.message);
    end
end
report.Ready = isempty(report.Errors) && report.StatisticsLicenseTest;
nscc_util('writejson',path,report);
disp(report);
assert(report.Ready,'WiDS:ProbeFailed', ...
    'Environment probe failed. Read %s before scheduling pilot jobs.',path);
end
