"""No MATLAB or scheduler calls. Tests isolate pooling and corruption handling."""
import copy
import csv
import importlib.util
import math
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("nscc", ROOT / "nscc.py")
nscc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nscc)


class PackageChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.configs, cls.jobs, cls.protocol = nscc.manifests()
        cls.truth = nscc.expected_validation()

    def setUp(self):
        base = Path(os.environ.get('WIDS_TEST_TEMP', str(ROOT/'work'))).resolve()
        base.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=base)
        assert Path(self.temp.name).resolve().parent == base
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run = self.root / 'results/test'
        self.run.mkdir(parents=True)
        self.context = dict(PackageSHA256='a'*64, RunTag='test', Threads=4,
                            MATLABVersion='synthetic', MATLABRelease='synthetic',
                            Architecture='synthetic', StatsVersion='synthetic')
        nscc.write_json(self.run / 'probe.json', dict(Ready=True, Context=self.context))

    def fake_result(self, job_id, offset):
        job = self.jobs[job_id-1]
        config = next(c for c in self.configs if c['ID'] == job['ConfigID'])
        truth = self.truth[job['FoldIndex']]
        directory = self.run / 'jobs' / ('job_%04d' % job_id)
        directory.mkdir(parents=True, exist_ok=True)
        prediction = directory / 'predictions.csv'
        with prediction.open('w', newline='', encoding='utf-8') as handle:
            writer = csv.writer(handle)
            writer.writerow(['id', 'site_eui', 'prediction'])
            writer.writerows((identifier, y, y+offset) for identifier,y in truth)
        errors = [(y+offset)-y for _,y in truth]
        sse = math.fsum(e*e for e in errors)
        sae = math.fsum(abs(e) for e in errors)
        result = dict(Status='complete', Identity=dict(Context=self.context, Job=job, Config=config),
                      N=len(truth), NFit=(22054 if job['FoldIndex']==1 else 35000), SSE=sse, SAE=sae,
                      RMSE=math.sqrt(sse/len(truth)), MAE=sae/len(truth), FitSeconds=1,
                      PredictionsSHA256=nscc.sha256(prediction))
        nscc.write_json(directory/'result.json',result)
        return result, directory

    def aggregate(self):
        with patch.object(nscc,'verify',return_value='a'*64), \
             patch.object(nscc,'manifests',return_value=(self.configs,self.jobs,self.protocol)), \
             patch.object(nscc,'expected_validation',return_value=self.truth):
            return nscc.aggregate(self.root,'test')

    def test_frozen_protocol_and_manifests(self):
        self.assertEqual(len(self.configs),25)
        self.assertEqual(len(self.jobs),50)
        self.assertEqual([j['JobID'] for j in self.jobs],list(range(1,51)))
        self.assertEqual(len(self.truth[1]),12946)
        self.assertEqual(len(self.truth[2]),18308)
        self.assertEqual(sum(c['Stage']=='pilot' for c in self.configs),4)
        for family in ('forest','kernel','net'):
            self.assertEqual(sum(c['Stage']=='compare' and c['Family']==family for c in self.configs),6)

    def test_pooled_rmse_is_weighted_by_rows(self):
        self.fake_result(1,1)
        self.fake_result(2,3)
        rows,_ = self.aggregate()
        row=rows[0]
        expected=math.sqrt((12946+9*18308)/31254)
        self.assertAlmostEqual(row['PooledRMSE'],expected)
        self.assertAlmostEqual(row['PooledMAE'],(12946+3*18308)/31254)
        self.assertNotAlmostEqual(row['PooledRMSE'],2)
        with (self.run/'leaderboard.csv').open() as handle:
            self.assertEqual(list(csv.DictReader(handle)),[])  # Pilot never enters comparison rank.

    def test_one_fold_never_ranked(self):
        self.fake_result(1,1)
        rows,_=self.aggregate()
        self.assertEqual(rows[0]['CompletedFolds'],1)
        self.assertNotIn('PooledRMSE',rows[0])

    def test_invalid_context_excluded(self):
        result,directory=self.fake_result(1,1)
        result['Identity']['Context']=dict(self.context,Threads=8)
        nscc.write_json(directory/'result.json',result)
        rows,details=self.aggregate()
        self.assertEqual(rows[0]['CompletedFolds'],0)
        self.assertTrue(details[0]['Status'].startswith('invalid'))

    def test_nan_metric_excluded(self):
        result,directory=self.fake_result(1,1)
        # JSON null is what MATLAB jsonencode emits for many nonfinite values.
        result['SSE']=None
        nscc.write_json(directory/'result.json',result)
        _,details=self.aggregate()
        self.assertIn('invalid',details[0]['Status'])

    def test_checksum_tampering_excluded(self):
        _,directory=self.fake_result(1,1)
        with (directory/'predictions.csv').open('a') as handle:
            handle.write('999,1,2\n')
        _,details=self.aggregate()
        self.assertIn('checksum',details[0]['Status'])

    def test_duplicate_id_rejected_even_with_updated_checksum(self):
        result,directory=self.fake_result(1,1)
        path=directory/'predictions.csv'
        lines=path.read_text().splitlines()
        lines[2]=lines[1]
        path.write_text('\n'.join(lines)+'\n')
        result['PredictionsSHA256']=nscc.sha256(path)
        nscc.write_json(directory/'result.json',result)
        _,details=self.aggregate()
        self.assertIn('ID/order/target',details[0]['Status'])

    def test_false_target_rejected(self):
        result,directory=self.fake_result(1,1)
        path=directory/'predictions.csv'
        lines=path.read_text().splitlines()
        fields=lines[1].split(',')
        fields[1]=str(float(fields[1])+1)
        lines[1]=','.join(fields)
        path.write_text('\n'.join(lines)+'\n')
        result['PredictionsSHA256']=nscc.sha256(path)
        nscc.write_json(directory/'result.json',result)
        _,details=self.aggregate()
        self.assertIn('ID/order/target',details[0]['Status'])

    def test_profile_placeholder_and_runtime_guard(self):
        p=nscc.read_json(ROOT/'config/cluster.example.json')
        path=self.root/'cluster.json'
        nscc.write_json(path,p)
        with self.assertRaisesRegex(ValueError,'Confirm'):
            nscc.load_profile(path)
        p.update(system='fixture',scheduler='PBS_PRO',allocation_confirmed=True,
                 project='fixture123',queue='fixtureQ',modules=['matlab/2024b_runtime'])
        nscc.write_json(path,p)
        with self.assertRaisesRegex(ValueError,'Runtime'):
            nscc.load_profile(path)
        p['modules']=[]
        nscc.write_json(path,p)
        self.assertEqual(nscc.load_profile(path)['cpus'],4)

    def test_payload_hash_mismatch(self):
        (self.root/'SHA256SUMS').write_text('a'*64+'  changed.txt\n')
        (self.root/'changed.txt').write_text('tampered')
        with self.assertRaisesRegex(ValueError,'Checksum mismatch'):
            nscc.verify(self.root)

    def test_pbs_cpu_and_quoting(self):
        import shlex
        profile=nscc.read_json(ROOT/'config/cluster.example.json')
        profile.update(project='FIXTURE_PROJECT',queue='FIXTURE_QUEUE',modules=['matlab/FIXTURE_FULL'],
                       matlab_executable='/app/Full MATLAB/bin/matlab',modules_init='/etc/FIXTURE modules.sh')
        script=nscc.pbs_text(profile,'/scratch/FIXTURE/wids_nscc','a'*64,self.jobs[0])
        self.assertIn('#PBS -P FIXTURE_PROJECT\n',script)
        self.assertIn('#PBS -q FIXTURE_QUEUE\n',script)
        self.assertIn('ncpus=4:mem=32gb',script)
        self.assertNotIn('ngpus',script)
        self.assertNotIn('parpool',script)
        self.assertIn('WIDS_JOB_ID=1',script)
        self.assertIn('WIDS_MAX_THREADS=4',script)
        calls=[line.strip() for line in script.splitlines() if ' -batch ' in line]
        command=shlex.split(calls[-1])
        self.assertEqual(command,[profile['matlab_executable'],'-batch',"addpath('matlab'); nscc_run_job"])
        for bad_root in ('/path with spaces/package',"/path'quote/package",'C:\\windows'):
            with self.assertRaises(ValueError):
                nscc.pbs_text(profile,bad_root,'a'*64,None)

    def test_comparison_config_enters_leaderboard(self):
        self.fake_result(9,1)
        self.fake_result(10,2)
        self.aggregate()
        with (self.run/'leaderboard.csv').open() as handle:
            rows=list(csv.DictReader(handle))
        self.assertEqual([r['ConfigID'] for r in rows],[self.jobs[8]['ConfigID']])

    def test_no_submission_in_code(self):
        import ast
        tree=ast.parse((ROOT/'nscc.py').read_text())
        # All scheduler submission remains a user-run qsub command in text.
        calls=[n for n in ast.walk(tree) if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute)
               and isinstance(n.func.value,ast.Name) and n.func.value.id=='subprocess']
        self.assertEqual(len(calls),1)
        self.assertEqual(calls[0].func.attr,'run')  # read-only discover()


if __name__=='__main__':
    unittest.main(verbosity=2)
