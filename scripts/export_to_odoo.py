#!/usr/bin/env python3
"""Convert an explicitly mapped survey CSV into Odoo CRM import rows; never contacts Odoo."""
import argparse,csv,os
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path)
for name in ['name','email','message','consent']:p.add_argument('--'+name+'-column',required=True)
a=p.parse_args()
if a.input.resolve()==a.output.resolve():p.error('Usar salida distinta del origen')
def safe(s):
    s=(s or '').strip()
    return "'"+s if s.lstrip().startswith(('=','+','-','@')) else s
rows=[];skipped=0
with a.input.open(encoding='utf-8-sig',newline='') as f:
    reader=csv.DictReader(f);needed=[a.name_column,a.email_column,a.message_column,a.consent_column]
    if not reader.fieldnames or any(k not in reader.fieldnames for k in needed):p.error('Faltan columnas; revisar encabezado exportado')
    for row in reader:
        if (row[a.consent_column] or '').strip().lower() not in ['si','sí','yes','true','1']:skipped+=1;continue
        email=(row[a.email_column] or '').strip()
        if not email or '@' not in email:skipped+=1;continue
        name=(row[a.name_column] or '').strip()
        rows.append({'name':safe('Solicitud web · '+(name or email)),'contact_name':safe(name),'email_from':safe(email),'description':safe(row[a.message_column])})
fd=os.open(a.output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w',encoding='utf-8',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=['name','contact_name','email_from','description']);writer.writeheader();writer.writerows(rows)
print(f'{len(rows)} filas convertidas; {skipped} omitidas. Revisar y probar importacion antes de usar datos reales.')
