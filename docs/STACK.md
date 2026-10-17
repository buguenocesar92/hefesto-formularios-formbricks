# Decisión de stack y portabilidad
El Compose se deriva de la etiqueta 6.0.2, no de main. Se fija la app 6.0.2 y Cube 1.7.47-1. El Compose de esa versión referencia Hub latest: el kit resuelve su digest el 16-10-2026 y añade el worker que distribuye esa imagen. La compatibilidad conjunta de estos binarios requiere la prueba real descrita en aceptación; fijar digest da repetibilidad, no demuestra compatibilidad. No se utilizan versiones viejas para reducir dependencias.

Se conservan los servicios oficiales de migración y la preparación inicial de autorización. Se eliminan perfiles opcionales taxonomy/vLLM, puertos públicos y carga indiscriminada de .env en la app; se añaden volúmenes explícitos, Mailpit privado, comprobación de variables y respaldo. AUTHZED_ENABLED=true, fully_consistent; no se desactiva autorización para simplificar.

## Supabase
La configuración oficial de esta versión parte de pgvector/PostgreSQL18 y crea otra base/rol para SpiceDB mediante un administrador. Un proyecto Supabase no equivale sin más a ese servidor: su rol administrador está gestionado y existen esquemas/servicios reservados. Para adaptar habría que decidir dónde vive SpiceDB, usar un rol de app para Formbricks/Hub, revisar extensión vector y search_path, validar migraciones con una conexión de sesión y configurar TLS verificado en Prisma/Hub/Cube/SpiceDB. También se tendría que respaldar y recuperar conjuntamente autorización, DB y colas.

Por ello este kit conserva el PostgreSQL nativo local y no trae DSN de Supabase ni afirma que esté integrado. Otras aplicaciones de Hefesto ya preparadas para PostgreSQL externo pueden seguir usando sus proyectos Supabase independientes.

## Límites
No hay portal multicliente de marca blanca, facturación ni aislamiento automático entre organizaciones de distintos clientes. Una instalación por cliente facilita separar acceso, datos y mantenimiento. No desbloquear funciones EE modificando comprobaciones. Conservar LICENSE-Formbricks.txt y revisar las licencias de componentes/EE antes de distribuir modificaciones o vender funciones licenciadas.

SMTP nativo en este kit: TLS implícito 465; para otro puerto/proveedor revisar y probar los ajustes oficiales, no desactivar validación TLS. No se programa un cron externo ni se dan por probadas las funciones que lo requieran. OAuth, RAG, IA, webhooks hacia clientes y S3 permanecen sin configurar.
