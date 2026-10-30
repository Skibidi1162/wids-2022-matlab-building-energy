function [Xfit, Xval, schema] = nscc_encode(fitTable, valTable, names)
%NSCC_ENCODE Fitting-only numeric scaling and explicit categorical expansion.
% Source predictors remain the frozen 59. Dummies are a representation only.
names = string(names(:));
Xfit = zeros(height(fitTable),0);
Xval = zeros(height(valTable),0);
schema = struct('SourcePredictors',names,'Columns',strings(0,1), ...
    'Numeric',struct,'CategoryLevels',struct);
for j = 1:numel(names)
    name = names(j);
    a = fitTable.(name); b = valTable.(name);
    if iscategorical(a)
        levels = string(categories(a));
        assert(isequal(categories(a),categories(b)), ...
            'WiDS:Vocabulary','Category vocabularies differ.');
        schema.CategoryLevels.(name) = levels;
        af = double(a); bv = double(b);
        assert(all(isfinite(af)) && all(isfinite(bv)), ...
            'WiDS:Missing','Undefined category in %s.',name);
        for k = 1:numel(levels)
            Xfit(:,end+1) = double(af==k); %#ok<AGROW>
            Xval(:,end+1) = double(bv==k); %#ok<AGROW>
            schema.Columns(end+1,1) = name + "==" + levels(k);
        end
    else
        a = double(a); b = double(b);
        assert(all(isfinite(a)) && all(isfinite(b)), ...
            'WiDS:Missing','Unexpected nonfinite numeric input: %s.',name);
        mu = mean(a); sigma = std(a,0);
        if sigma==0, sigma=1; end
        schema.Numeric.(name) = struct('Mean',mu,'Std',sigma);
        Xfit(:,end+1) = (a-mu)/sigma; %#ok<AGROW>
        Xval(:,end+1) = (b-mu)/sigma; %#ok<AGROW>
        schema.Columns(end+1,1) = name;
    end
end
assert(all(isfinite(Xfit(:))) && all(isfinite(Xval(:))), ...
    'WiDS:Encoding','Nonfinite encoded matrix.');
end
