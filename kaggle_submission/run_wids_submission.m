function info = run_wids_submission(stage)
%RUN_WIDS_SUBMISSION Run one stage per call to bound connector run duration.
% Stages: prepare, residual, boost, forest, export (in that order).
arguments
    stage (1,1) string {mustBeMember(stage,["prepare","residual","boost","forest","export"])}
end
switch stage
    case "prepare"
        info=wids_submission_prepare();
    case {"residual","boost","forest"}
        info=wids_submission_fit(stage);
    case "export"
        info=wids_submission_export();
end
end
