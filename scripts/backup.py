#!/usr/bin/env python3
import datetime,json,os,shutil
from common import ROOT,CONFIG,VOLUMES,SERVICES,dc,sha
os.umask(0o077)
for n in CONFIG:
    if not (ROOT/n).is_file():raise SystemExit('Falta archivo '+n)
running=dc('ps','--services','--status','running',capture_output=True,text=True).stdout.split()
if any(s not in SERVICES+['mailpit'] for s in running):raise SystemExit('Hay servicios de inicializacion/operaciones activos; terminar antes del respaldo')
running=[s for s in SERVICES if s in running]
p=ROOT/'backups'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ');p.mkdir(parents=True,mode=0o700)
try:
    dc('stop','--timeout','120',*SERVICES)
    # No escribir un archivo del motor mientras sus procesos siguen activos.
    if dc('ps','--services','--status','running',*SERVICES,capture_output=True,text=True).stdout.strip():raise SystemExit('Servicios siguen activos; no se copia')
    for v in VOLUMES:
        with (p/(v+'.tar.gz')).open('wb') as f:dc('run','--rm','--no-deps','-T','--entrypoint','tar','backup-tools','-czf','-','-C','/volumes/'+v,'.',stdout=f)
    for n in CONFIG:
        dst=p/n;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/n,dst)
    files=CONFIG+[v+'.tar.gz' for v in VOLUMES]
    (p/'manifest.json').write_text(json.dumps({'product':'hefesto-formularios','version':'6.0.2','status':'completed','sha256':{n:sha(p/n) for n in files}},indent=2))
    print('Respaldo frio completado:',p,'Contiene datos personales, sesiones y secretos; cifrar fuera del VPS.')
finally:
    if running:dc('start',*reversed(running))
