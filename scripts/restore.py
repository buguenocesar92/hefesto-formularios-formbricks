#!/usr/bin/env python3
import sys
from common import ROOT,CONFIG,VOLUMES,dc,verify,sha
if len(sys.argv)!=3 or sys.argv[2]!='--accept-restored-jobs':raise SystemExit('Uso: python3 scripts/restore.py /ruta/respaldo --accept-restored-jobs (recupera sesiones, colas y tareas)')
p=verify(sys.argv[1])
# Usar misma configuracion de motor/codigo/secretos. El nombre del proyecto y URLs pueden variar en .env.
for n in CONFIG:
    if n=='.env':continue
    if not (ROOT/n).is_file() or sha(ROOT/n)!=sha(p/n):raise SystemExit('Kit/configuracion diferente: '+n)
def env_values(file):
    values={}
    for line in file.read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            k,v=line.split('=',1);values[k.strip()]=v.strip().strip("\"'")
    return values
origin=env_values(p/'.env');target=env_values(ROOT/'.env')
for key in ['POSTGRES_PASSWORD','AUTHZED_DATABASE_PASSWORD','AUTHZED_TOKEN','NEXTAUTH_SECRET','ENCRYPTION_KEY','CRON_SECRET','HUB_API_KEY','CUBEJS_API_SECRET']:
    if not origin.get(key) or origin[key]!=target.get(key):raise SystemExit('Conservar secreto original: '+key)
if dc('ps','--services' ,'--status','running',capture_output=True,text=True).stdout.strip():raise SystemExit('Destino debe estar completamente detenido')
for v in VOLUMES:
    out=dc('run','--rm','--no-deps','-T','--entrypoint','find','backup-tools','/volumes/'+v,'-mindepth','1','-print','-quit',capture_output=True,text=True).stdout.strip()
    if out:raise SystemExit('Volumen destino no vacio: '+v)
for v in VOLUMES:
    with (p/(v+'.tar.gz')).open('rb') as f:dc('run','--rm','--no-deps','-T','--entrypoint','tar','backup-tools','-xzf','-','-C','/volumes/'+v,stdin=f)
print('Volumenes restaurados. No se arranca automaticamente. Ensayar con red interna y Mailpit; pueden reaparecer sesiones, colas y webhooks.')
