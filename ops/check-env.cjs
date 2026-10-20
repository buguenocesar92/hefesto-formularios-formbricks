const e=process.env;
const fail=m=>{console.error(m);process.exit(1)};
for(const k of ['NEXTAUTH_SECRET','ENCRYPTION_KEY','CRON_SECRET','HUB_API_KEY','CUBEJS_API_SECRET'])
 if(!/^[a-f0-9]{64}$/.test(e[k]||''))fail(`Configurar ${k}: 64 caracteres hexadecimales`);
let u;try{u=new URL(e.WEBAPP_URL)}catch{fail('WEBAPP_URL invalida')}
const local=e.BOOTSTRAP_MODE==='true';
if(u.username||u.password||u.search||u.hash||u.pathname!=='/')fail('Usar dominio raiz sin parametros');
if(local){if(e.WEBAPP_URL!=='http://localhost:8111')fail('Bootstrap solo http://localhost:8111')}
else{
 if(u.protocol!=='https:')fail('HTTPS requerido');
 if(e.OPERATOR_ACCOUNT_CREATED!=='true')fail('Crear y comprobar cuenta operadora en bootstrap');
 if(e.SMTP_READY==='true'){
  if(!e.SMTP_HOST||e.SMTP_HOST==='REEMPLAZAR'||!e.SMTP_USER||!e.SMTP_PASSWORD||e.SMTP_PASSWORD==='REEMPLAZAR')fail('Completar SMTP real');
  if(e.SMTP_PORT!=='465'||e.SMTP_SECURE_ENABLED!=='1')fail('Este kit configura SMTP TLS implicito en 465');
 }else{
  if(e.EMAIL_VERIFICATION_DISABLED!=='1')fail('Con SMTP_READY!=true, fijar EMAIL_VERIFICATION_DISABLED=1');
  if(e.PASSWORD_RESET_DISABLED!=='1')fail('Con SMTP_READY!=true, fijar PASSWORD_RESET_DISABLED=1');
 }
}
if(e.NEXTAUTH_URL!==e.WEBAPP_URL)fail('NEXTAUTH_URL debe coincidir con WEBAPP_URL');
console.log('Variables de servicio validadas; no se han probado credenciales SMTP ni estado de cuenta.');
