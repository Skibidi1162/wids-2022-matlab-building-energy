function [fitHistory,valHistory,audit] = wids_past_building_features(fitRaw,valRaw)
%WIDS_PAST_BUILDING_FEATURES Strictly past, fitting-label building histories.
% Match the exact RAW five-key tuple before any imputation. This tuple is a
% proxy for building identity; it is not a guaranteed unique building ID.
% For a query in year t, only fitting rows in years < t can supply history.
% Duplicate key-year observations are averaged first, then each observed year
% receives equal weight in history_mean_eui. Missing responses are ignored.
% Ratings use the latest past nonmissing fitting rating, independently of
% response availability. Raw year_built==0 and missing raw values are kept.
% valRaw need not contain site_eui; validation responses are never accessed.
arguments
    fitRaw table
    valRaw table
end

keyFields=["State_Factor","building_class","facility_type", ...
    "floor_area","year_built"];
required=[keyFields,"Year_Factor","energy_star_rating"];
assert(all(ismember(required,string(fitRaw.Properties.VariableNames))), ...
    'WiDS:HistoryInputs','Fitting data is missing a required predictor.');
assert(all(ismember(required,string(valRaw.Properties.VariableNames))), ...
    'WiDS:HistoryInputs','Validation data is missing a required predictor.');
assert(ismember("site_eui",string(fitRaw.Properties.VariableNames)), ...
    'WiDS:HistoryInputs','Fitting data must supply site_eui.');
nFit=height(fitRaw);nVal=height(valRaw);nQuery=nFit+nVal;
fitYear=numericColumn(fitRaw.Year_Factor,nFit,"Year_Factor");
valYear=numericColumn(valRaw.Year_Factor,nVal,"Year_Factor");
queryYear=[fitYear;valYear];
assert(all(isfinite(queryYear) & queryYear==fix(queryYear)), ...
    'WiDS:HistoryYears','Query years must be finite integers.');
fitEUI=numericColumn(fitRaw.site_eui,nFit,"site_eui");
assert(all(isfinite(fitEUI) | isnan(fitEUI)), ...
    'WiDS:HistoryResponses','Fitting responses cannot be infinite.');
fitRating=numericColumn(fitRaw.energy_star_rating,nFit,"energy_star_rating");
valRating=numericColumn(valRaw.energy_star_rating,nVal,"energy_star_rating");
assert(all(isfinite([fitRating;valRating]) | isnan([fitRating;valRating])), ...
    'WiDS:HistoryRatings','Raw ratings cannot be infinite.');
queryRating=[fitRating;valRating];

% Joint grouping uses predictor keys only, never validation responses.
fitKey=rawKeys(fitRaw);valKey=rawKeys(valRaw);
[allKeys,~,queryGroup]=unique([fitKey;valKey]);
nKey=numel(allKeys);fitGroup=queryGroup(1:nFit);
sourceYears=unique(fitYear);nSourceYears=numel(sourceYears);

names={'history_available','history_years','history_latest_eui', ...
    'history_mean_eui','history_previous_eui','history_year_gap', ...
    'history_latest_rating','history_rating_change'};
features=NaN(nQuery,numel(names));features(:,1:2)=0;
historyYears=zeros(nKey,1);sumYearEUI=zeros(nKey,1);
latestEUI=NaN(nKey,1);previousEUI=NaN(nKey,1);latestEUIYear=NaN(nKey,1);
latestRating=NaN(nKey,1);latestRatingYear=NaN(nKey,1);
pastConflict=false(nKey,1);queryPastConflict=false(nQuery,1);
duplicateGroups=zeros(nSourceYears,1);duplicateExtraRows=duplicateGroups;
conflictingLabelGroups=duplicateGroups;observedLabelGroups=duplicateGroups;

% One update per fitting year (six at most for the competition training set).
% After year s is added, answer queries in (s,next fitting year]. Queries in
% the earliest fitting year keep the initial empty-history values.
for yearIndex=1:nSourceYears
    sourceYear=sourceYears(yearIndex);
    rows=fitYear==sourceYear;
    groups=fitGroup(rows);labels=fitEUI(rows);ratings=fitRating(rows);
    counts=accumarray(groups,1,[nKey,1],@sum,0);
    duplicateGroups(yearIndex)=sum(counts>1);
    duplicateExtraRows(yearIndex)=sum(max(counts-1,0));

    valid=isfinite(labels);
    labelCounts=accumarray(groups(valid),1,[nKey,1],@sum,0);
    labelSums=accumarray(groups(valid),labels(valid),[nKey,1],@sum,0);
    observed=labelCounts>0;
    observedLabelGroups(yearIndex)=sum(observed);
    minima=accumarray(groups(valid),labels(valid),[nKey,1],@min,Inf);
    maxima=accumarray(groups(valid),labels(valid),[nKey,1],@max,-Inf);
    conflicts=labelCounts>1 & maxima>minima;
    conflictingLabelGroups(yearIndex)=sum(conflicts);
    pastConflict=pastConflict | conflicts;

    annualMeans=labelSums(observed)./labelCounts(observed);
    previousEUI(observed)=latestEUI(observed);
    latestEUI(observed)=annualMeans;
    latestEUIYear(observed)=sourceYear;
    historyYears(observed)=historyYears(observed)+1;
    sumYearEUI(observed)=sumYearEUI(observed)+annualMeans;

    validRating=isfinite(ratings);
    ratingCounts=accumarray(groups(validRating),1,[nKey,1],@sum,0);
    ratingSums=accumarray(groups(validRating),ratings(validRating),[nKey,1],@sum,0);
    observedRating=ratingCounts>0;
    latestRating(observedRating)=ratingSums(observedRating)./ratingCounts(observedRating);
    latestRatingYear(observedRating)=sourceYear;

    queryRows=queryYear>sourceYear;
    if yearIndex<nSourceYears
        queryRows=queryRows & queryYear<=sourceYears(yearIndex+1);
    end
    group=queryGroup(queryRows);year=queryYear(queryRows);
    labelYear=latestEUIYear(group);ratingYear=latestRatingYear(group);
    assert(all(isnan(labelYear) | labelYear<year), ...
        'WiDS:HistoryLeakage','An EUI history source is not strictly earlier.');
    assert(all(isnan(ratingYear) | ratingYear<year), ...
        'WiDS:HistoryLeakage','A rating history source is not strictly earlier.');
    count=historyYears(group);hasHistory=count>0;
    meanEUI=NaN(numel(group),1);
    meanEUI(hasHistory)=sumYearEUI(group(hasHistory))./count(hasHistory);
    features(queryRows,:)=[double(hasHistory),count,latestEUI(group), ...
        meanEUI,previousEUI(group),year-labelYear,latestRating(group), ...
        queryRating(queryRows)-latestRating(group)];
    queryPastConflict(queryRows)=pastConflict(group);
end

allHistory=array2table(features,'VariableNames',names);
fitHistory=allHistory(1:nFit,:);valHistory=allHistory(nFit+1:end,:);
fitHasHistory=features(1:nFit,1)>0;valHasHistory=features(nFit+1:end,1)>0;
audit=struct('KeyFields',keyFields,'FitRows',nFit,'ValidationRows',nVal, ...
    'DistinctFittingKeys',numel(unique(fitKey)), ...
    'DistinctValidationKeys',numel(unique(valKey)), ...
    'SourceYears',sourceYears, ...
    'DuplicateSameKeyYearGroups',sum(duplicateGroups), ...
    'DuplicateSameKeyYearExtraRows',sum(duplicateExtraRows), ...
    'ConflictingSameKeyYearLabelGroups',sum(conflictingLabelGroups), ...
    'FitRowsWithConflictingPastLabels',sum(queryPastConflict(1:nFit)), ...
    'ValidationRowsWithConflictingPastLabels',sum(queryPastConflict(nFit+1:end)), ...
    'FitRowsWithHistory',sum(fitHasHistory), ...
    'ValidationRowsWithHistory',sum(valHasHistory), ...
    'FitHistoryCoverage',mean(double(fitHasHistory)), ...
    'ValidationHistoryCoverage',mean(double(valHasHistory)), ...
    'LatestSourceYearStrictlyPast',true,'ValidationTargetRequired',false);
audit.BySourceYear=table(sourceYears,duplicateGroups,duplicateExtraRows, ...
    conflictingLabelGroups,observedLabelGroups,'VariableNames', ...
    {'SourceYear','DuplicateGroups','DuplicateExtraRows', ...
    'ConflictingLabelGroups','ObservedLabelGroups'});
end

function key = rawKeys(raw)
% Length-prefixed text plus fixed-width IEEE-754 numeric tokens avoids
% delimiter collisions and decimal rounding collisions. Missing text has a
% distinct token, so it cannot collide with a literal string such as <missing>.
n=height(raw);
key=textToken(raw.State_Factor,n)+textToken(raw.building_class,n)+ ...
    textToken(raw.facility_type,n)+numericToken(raw.floor_area,n,"floor_area")+ ...
    numericToken(raw.year_built,n,"year_built");
end

function token = textToken(value,n)
value=string(value);value=value(:);
assert(numel(value)==n,'WiDS:HistoryKey','A text key must be a scalar column.');
missing=ismissing(value);token=repmat("M|",n,1);
token(~missing)="S"+string(strlength(value(~missing)))+":"+value(~missing)+"|";
end

function token = numericToken(value,n,name)
value=numericColumn(value,n,name);
value(value==0)=0; % Canonicalize signed zero to its numeric equality class.
value(isnan(value))=NaN; % Canonicalize all missing numeric key values.
if n==0,token=strings(0,1);return,end
token="N"+string(num2hex(value))+"|";
end

function value = numericColumn(value,n,name)
assert(isnumeric(value) && isreal(value) && size(value,2)==1 && numel(value)==n, ...
    'WiDS:HistoryInputs','%s must be a real numeric scalar column.',name);
if isinteger(value)
    assert(all(abs(double(value))<=flintmax), ...
        'WiDS:HistoryInputs','%s contains integers that cannot safely be converted to double.',name);
end
value=double(value);
end
