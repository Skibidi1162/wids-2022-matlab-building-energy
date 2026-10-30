# WiDS Datathon 2022: lessons from the leading solutions

The final **private leaderboard** and the teams' published writeups were reviewed to guide our next experiments. These are competition test-set results. They cannot be compared directly with our RMSE on historical validation years 4 and 5, which contain different buildings and target values.

| Final private rank | Team | RMSE | Published solution |
| --- | --- | ---: | --- |
| 1 | ZUJM | 17.842 | [First-place writeup](https://www.kaggle.com/competitions/widsdatathon2022/writeups/zujm-first-place-solution) |
| 2 | Dihydrogen Oxide | 18.267 | [Second-place writeup](https://www.kaggle.com/competitions/widsdatathon2022/writeups/dihydrogen-oxide-second-place-solution) |
| 3 | Gradient Boosted Math Ladies | 18.545 | [Third-place writeup](https://www.kaggle.com/competitions/widsdatathon2022/writeups/gradient-boosted-math-ladies-third-place-solution) |

The [official WiDS results article](https://www.widsworldwide.org/get-inspired/blog/wids-datathon-impact-2022/) independently confirms the winning teams. The methods below summarize their writeups; we have not reproduced their complete pipelines or independently verified every linked notebook.

## What the teams did

**First place:** ZUJM separated buildings with usable history from buildings without it. Their history features included earlier EUI and energy ratings, lags, rolling averages, changes, and trends. They combined LightGBM, CatBoost, and AutoML predictions, with weather and seasonal summaries. Their separate no-history approach and optional pseudo-labeling addressed buildings where earlier consumption could not be recovered. The central lesson is that identifying repeated buildings can expose more useful information than simply increasing model complexity. Their writeup links [history](https://www.kaggle.com/jayjay75/part-1-wids2022-model-with-lag) and [no-history](https://www.kaggle.com/mathurinache/part2-wids2022-model2-no-lag) notebooks.

**Second place:** Dihydrogen Oxide matched 9,067 of 9,705 test buildings using `State_Factor`, `building_class`, `facility_type`, `floor_area`, and `year_built`. Earlier EUI was especially valuable. Their approach branched by history and rating availability, using XGBoost and LightGBM for direct consumption or relative changes, plus rating-based linear relationships where sufficiently consistent. They also considered weather differences and used year 6 for validation. This supports testing a simple historical-consumption baseline before a large model search.

**Third place:** Gradient Boosted Math Ladies used LightGBM throughout. A strict building identifier combined state, facility type, area, construction year, and elevation; a looser grouping omitted elevation. They engineered historical EUI, rating, and weather features, including weighted heating-season temperatures. Initial models handled buildings without history; later models combined history with initial-model predictions through `init_score`. Their final prediction averaged three second-stage models. The useful lesson is a history model with a deliberate fallback for unmatched buildings.

## Priorities for our project

1. **Test history features locally first.** Match buildings using raw stable attributes, audit collisions and missing keys, and average duplicate building-year observations before constructing historical values. Use only years earlier than each training or validation row. Compare latest available EUI, calendar lags, and historical means with the current model. Report RMSE for buildings with and without usable history, alongside pooled RMSE on the same year-4/year-5 splits.
2. **Keep implementation in local MATLAB.** The winning libraries are references for their methods; they are not native MATLAB estimators. Our MATLAB experiments adapt the history features, direct/residual regression, bagging, boosted trees, and prediction blending using Statistics and Machine Learning Toolbox. Use the tested local CPU workflow for comparisons. Any later external-library integration would be a separate scope decision.
3. **Ablate borrowed ideas.** Some solutions capped or excluded high EUI values. We should test that choice rather than assume these observations are invalid. Likewise, `floor_area * ELEVATION` is an empirical interaction, not physical building size. Seasonal features, pseudo-labeling, and further blends should earn their place through the same validation protocol.

Our historical folds are model-selection data. Any resulting gain remains a local validation result until assessed on a separate evaluation set or Kaggle submission.
