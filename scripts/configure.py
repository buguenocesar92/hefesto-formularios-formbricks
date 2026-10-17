#!/usr/bin/env python3
import os,secrets
from pathlib import Path
r=Path(__file__).resolve().parents[1];s=(r/'.env.example').read_text()
for key in ['POSTGRES','AUTHZED_DB','AUTHZED_TOKEN','AUTH','ENCRYPTION','CRON','HUB','CUBE']:s=s.replace('GENERAR_'+key+'\n',secrets.token_hex(32)+'\n')
fd=os.open(r/'.env',os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
with os.fdopen(fd,'w') as f:f.write(s)
print('.env creado con claves independientes y permiso 0600. No sobrescribe archivos existentes.')
