function prepared = nscc_prepare(foldIndex, family)
%NSCC_PREPARE Load the historical extract, refit cleaning for this fold only.
root = nscc_util('root');
protocol = nscc_util('readjson',fullfile(root,'manifests','protocol.json'));
fold = protocol.Folds(foldIndex);
opts = detectImportOptions(fullfile(root,'data','train_y1_y5.csv'), ...
    'VariableNamingRule','preserve');
opts = setvartype(opts,{'State_Factor','building_class','facility_type'},'string');
raw = readtable(fullfile(root,'data','train_y1_y5.csv'),opts);
assert(all(ismember(raw.Year_Factor,1:5)), ...
    'WiDS:ReservedYear','This runner accepts years 1-5 only.');
assert(height(raw)==53308 && numel(unique(raw.id))==height(raw), ...
    'WiDS:Data','Unexpected cohort size or duplicate IDs.');
fitRows = raw.Year_Factor>=1 & raw.Year_Factor<=fold.FitThrough;
valRows = raw.Year_Factor==fold.ValidationYear;
assert(nnz(fitRows)==fold.FitN && nnz(valRows)==fold.ValidationN, ...
    'WiDS:Fold','Temporal fold counts do not match the frozen protocol.');
fitRaw = raw(fitRows,:); valRaw = raw(valRows,:);
[fitClean,valClean,cleaning] = wids_clean_split(fitRaw,valRaw);
featureTable = readtable(fullfile(root,'reference', ...
    'wids_selected_baseline_features.csv'),'TextType','string');
names = featureTable.Predictor(:);
assert(numel(names)==59 && numel(unique(names))==59 && ...
    ~any(ismember(names,["id","Year_Factor","site_eui"])), ...
    'WiDS:Predictors','The 59-predictor baseline must remain frozen.');
assert(isequal(fitRaw.site_eui,fitClean.site_eui) && ...
    isequal(valRaw.site_eui,valClean.site_eui), ...
    'WiDS:Target','Targets changed during cleaning.');
A = fitClean(:,cellstr(names)); B = valClean(:,cellstr(names));
% Give the missingness flags an explicit numeric interpretation for all models.
for name = ["year_built_missing","energy_star_rating_missing"]
    A.(name) = double(A.(name)); B.(name) = double(B.(name));
end
prepared = struct('Fold',fold,'Family',family,'SourcePredictors',names, ...
    'Cleaning',cleaning,'FitIDs',fitRaw.id,'ValidationIDs',valRaw.id, ...
    'Yfit',double(fitRaw.site_eui),'Yval',double(valRaw.site_eui));
assert(all(isfinite(prepared.Yfit)) && all(isfinite(prepared.Yval)), ...
    'WiDS:Target','Targets must be finite; no rows may be dropped.');
prepared.ValidationUnknownCounts = struct;
for name = ["State_Factor","building_class","facility_type"]
    prepared.ValidationUnknownCounts.(name) = nnz(string(B.(name))=="__unknown__");
end
if strcmp(family,'forest')
    for name = names.'
        if ~iscategorical(A.(name))
            assert(all(isfinite(A.(name))) && all(isfinite(B.(name))), ...
                'WiDS:Missing','Unexpected nonfinite value in %s.',name);
        end
    end
    prepared.Xfit = A; prepared.Xval = B;
    prepared.Encoding = struct('Representation','native categorical table', ...
        'NumericStandardization',false);
    prepared.EncodedP = width(A);
else
    [prepared.Xfit,prepared.Xval,prepared.Encoding] = nscc_encode(A,B,names);
    prepared.EncodedP = size(prepared.Xfit,2);
end
end
