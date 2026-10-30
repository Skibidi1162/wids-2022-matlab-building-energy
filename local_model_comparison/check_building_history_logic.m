function check_building_history_logic()
%CHECK_BUILDING_HISTORY_LOGIC Exercise past-only history and duplicate semantics.
fit=table(repmat("S",5,1),repmat("Commercial",5,1),repmat("Office",5,1), ...
    [100;100;100;100;200],repmat(1950,5,1),[1;1;2;4;1], ...
    [10;14;20;999;50],[40;60;70;80;30], ...
    'VariableNames',{'State_Factor','building_class','facility_type','floor_area', ...
    'year_built','Year_Factor','site_eui','energy_star_rating'});
query=fit([1,1,5,1],:);query=removevars(query,'site_eui');
query.Year_Factor=[3;2;4;3];query.floor_area(4)=300;
query.energy_star_rating=[75;55;35;60];
[fitFeatures,features]=wids_past_building_features(fit,query);
assert(all(fitFeatures.history_available([1,2,5])==0));
assert(fitFeatures.history_latest_eui(3)==12);
assert(fitFeatures.history_latest_eui(4)==20);
assert(features.history_latest_eui(1)==20 && features.history_year_gap(1)==1);
assert(features.history_years(1)==2 && features.history_mean_eui(1)==16);
assert(features.history_previous_eui(1)==12);
assert(features.history_latest_rating(1)==70 && features.history_rating_change(1)==5);
assert(features.history_latest_eui(2)==12 && isnan(features.history_previous_eui(2)));
assert(features.history_latest_eui(3)==50 && features.history_year_gap(3)==3);
assert(features.history_available(4)==0 && isnan(features.history_latest_eui(4)));
changed=fit;changed.site_eui(4)=10000;
[changedFit,changedQuery]=wids_past_building_features(changed,query);
assert(isequaln(fitFeatures,changedFit) && isequaln(features,changedQuery), ...
    'Current/future labels affected earlier history.');
query.site_eui=[10000;-10000;0;Inf];
[~,changedQuery]=wids_past_building_features(fit,query);
assert(isequaln(features,changedQuery),'Query labels were used as history.');
fprintf('History checks passed: duplicate-year average, past-only labels, gaps, and target invariance.\n');
end
