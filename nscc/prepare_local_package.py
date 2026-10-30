"""Build a local NSCC data/checksum package. Never uploads or submits jobs."""
import csv,hashlib,json,sys
from pathlib import Path
root=Path(__file__).resolve().parent
source=Path(sys.argv[1]).resolve()
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
(root/'data').mkdir(exist_ok=True)
target=root/'data/train_y1_y5.csv'
counts={str(y):0 for y in range(1,6)}
with source.open(newline='',encoding='utf-8-sig') as src,target.open('w',newline='',encoding='utf-8') as dst:
 reader=csv.DictReader(src);writer=csv.DictWriter(dst,fieldnames=reader.fieldnames);writer.writeheader()
 for row in reader:
  if row['Year_Factor'] in counts:
   writer.writerow(row);counts[row['Year_Factor']]+=1
assert sum(counts.values())==53308
assert counts['4']==12946 and counts['5']==18308
p=root/'manifests/protocol.json';protocol=json.loads(p.read_text())
protocol['DataSHA256']=digest(target);protocol['DataRowCounts']=counts
protocol['SourceSHA256']={q.name:digest(q) for q in (root/'reference').iterdir() if q.is_file()}
protocol['SourceSHA256']['widsdatathon2022/train.csv']=digest(source)
p.write_text(json.dumps(protocol,indent=2),encoding='utf-8')
files=[q for q in root.rglob('*') if q.is_file() and q.name!='SHA256SUMS' and not any(x in q.relative_to(root).parts for x in ['results','work','__pycache__','.git']) and q.name!='cluster.local.json']
(root/'SHA256SUMS').write_text(''.join(digest(q)+'  '+q.relative_to(root).as_posix()+'\n' for q in sorted(files)),encoding='utf-8')
print('Prepared local years 1-5 and checksum manifest. No jobs submitted.')
