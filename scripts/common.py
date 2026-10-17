import hashlib,json,subprocess,tarfile
from pathlib import Path,PurePosixPath
ROOT=Path(__file__).resolve().parents[1]
CONFIG=['.env','compose.yaml','compose.bootstrap.yaml','compose.rehearsal.yaml','authzed-postgres-bootstrap.sh','cube/cube.js','cube/schema/FeedbackRecords.js','ops/check-env.cjs','docs/IMAGENES.json']
VOLUMES=['postgres','redis','uploads','saml']
SERVICES=['formbricks','hub','hub-worker','cube','spicedb','redis','postgres']
def dc(*a,**kw):return subprocess.run(['docker','compose','--project-directory',str(ROOT),'-f',str(ROOT/'compose.yaml'),*a],check=True,**kw)
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def safe_tar(path):
    seen=set();total=0;count=0
    with tarfile.open(path,'r|gz') as tf:
        for m in tf:
            n=PurePosixPath(m.name);count+=1
            if n.is_absolute() or '..' in n.parts or m.mode & 0o6000 or not (m.isdir() or m.isfile()):raise SystemExit('Tar contiene ruta o tipo no admitido')
            key=str(n)
            if key in seen:raise SystemExit('Tar contiene ruta duplicada')
            seen.add(key);total+=m.size
            if count>2000000 or total>500*1024**3:raise SystemExit('Tar excede limites de este kit')
    return total
def verify(folder):
    p=Path(folder).resolve();m=json.loads((p/'manifest.json').read_text())
    if (m.get('product'),m.get('version'),m.get('status'))!=('hefesto-formularios','6.0.2','completed'):raise SystemExit('Manifest incorrecto')
    expected=CONFIG+[v+'.tar.gz' for v in VOLUMES]
    if set(m.get('sha256',{}))!=set(expected):raise SystemExit('Lista de archivos inesperada')
    for n in expected:
        f=p/n
        if f.is_symlink() or not f.is_file() or p not in f.resolve().parents or sha(f)!=m['sha256'][n]:raise SystemExit('Ruta o checksum incorrecto: '+n)
    for v in VOLUMES:safe_tar(p/(v+'.tar.gz'))
    return p
