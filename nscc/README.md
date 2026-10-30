# NSCC MATLAB CPU benchmark prototype

This is a prototype for independent scheduler jobs. **No remote jobs have been submitted or verified.** Model fitting uses MATLAB and Statistics and Machine Learning Toolbox. Python 3.8+ standard-library code prepares scheduler scripts and validates aggregated results.

The public repository omits the original archive's competition data and its stale checksum manifest. After downloading the competition train.csv, rebuild a local package:

```bash
python prepare_local_package.py /absolute/path/to/train.csv
python nscc.py verify
python -m unittest discover -s tests
python nscc.py discover
```

The packaging script extracts only years 1â€“5, updates input/source checksums, and creates SHA256SUMS. These generated artifacts stay local. Confirm actual full MATLAB, toolbox licenses, project allocation, scheduler, modules, CPU queue, and filesystem before adapting config/cluster.example.json. The example does not authorize submitting jobs. Use `python nscc.py --help` for commands. The program never calls qsub.

The frozen prototype compares 59 baseline predictors and does not yet add the final project's history features. The published historical-fold metrics and Kaggle scores came from local MATLAB experiments, not this cluster code.
