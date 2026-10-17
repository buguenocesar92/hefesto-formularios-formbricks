# Hefesto Formularios · Formbricks 6.0.2
Kit de despliegue nativo para formularios, encuestas por enlace y feedback de clientes. Conserva el motor y la interfaz de Formbricks: no es una aplicación nueva ni una réplica visual. Incluye tres guías de cuestionarios y conversión de exportaciones para importar oportunidades en Odoo CRM.

## Stack elegido
Formbricks 6.0.2 + PostgreSQL 18 con pgvector + SpiceDB + Valkey + Formbricks Hub/API y worker + Cube. Se conservan las migraciones e inicialización de autorización oficiales; imágenes fijadas por digest. Las imágenes no están incluidas en el ZIP y deben descargarse.

Esta entrega usa PostgreSQL local. Formbricks usa PostgreSQL de forma nativa, pero eso por sí solo no demuestra que el stack completo v6 funcione en un proyecto Supabase: también hay otra base para SpiceDB, migraciones de Hub, roles, extensiones y conexión de Cube. No se incluye una configuración Supabase parcialmente conectada. Ver docs/STACK.md para la evaluación y el alcance.

Requisitos: servidor Linux con Docker Engine y Compose v2, Python 3.11+ y dominio HTTPS. Reservar como presupuesto inicial de prueba 4 CPU, 8 GB RAM y espacio suficiente para datos y copias; medir antes de comprometer capacidad comercial. No incluye GPU ni servicios de IA.

## Archivos
- compose.yaml: stack de servicio sin puertos de host; exponer solo formbricks:3000 mediante Coolify.
- compose.bootstrap.yaml: acceso local 8111 y buzón Mailpit 8029.
- compose.rehearsal.yaml: red interna para un ensayo de recuperación sin salida a Internet.
- scripts/: generación de entorno, respaldo frío de cuatro volúmenes, verificación, restauración y conversor CSV a Odoo.
- docs/FORMULARIOS.md: tres cuestionarios listos para crear en la interfaz.
- upstream/: Compose y README originales de la versión de referencia.

## Primera puesta en marcha privada
1. Descomprimir y entrar en esta carpeta. Ejecutar `python3 scripts/configure.py`. Genera ocho secretos independientes en .env con permiso 0600; falla si ya existe el archivo. No editar las claves generadas después de inicializar la BD.
2. Mantener el servicio privado. Validar y arrancar:

```sh
docker compose -f compose.yaml -f compose.bootstrap.yaml config --quiet
docker compose -f compose.yaml -f compose.bootstrap.yaml up -d
```

3. Esperar a que terminen formbricks-migrate, hub-migrate, authzed-db-bootstrap, spicedb-migrate, authzed-initialize y permissions. Revisar `docker compose -f compose.yaml -f compose.bootstrap.yaml ps -a` y logs de errores, sin copiarlos con datos sensibles.
4. Desde tu equipo: `ssh -L 8111:127.0.0.1:8111 -L 8029:127.0.0.1:8029 usuario@servidor`. Abrir http://localhost:8111 y http://localhost:8029. Mailpit captura el correo de prueba y no lo entrega a personas reales. No exponer estos puertos a Internet.
5. Crear la cuenta operadora mediante el flujo nativo. Verificar el correo en Mailpit y comprobar entrada, salida y recuperación de contraseña. Crear el primer espacio/proyecto y una encuesta ficticia. No hay administrador predeterminado ni seed con contraseña conocida.
6. Crear los cuestionarios de docs/FORMULARIOS.md y probar publicar una copia ficticia, responder y exportar. Las guías son especificaciones editables, no archivos de importación automática del editor.

## Correo real y preparación pública
Configurar en .env MAIL_FROM, SMTP_HOST, SMTP_PORT=465, SMTP_USER y SMTP_PASSWORD usando un proveedor con TLS implícito. El remitente/dominio debe estar verificado en ese proveedor. El kit habilita verificación y recuperación por correo y valida el certificado TLS. No incluye credenciales SMTP ni envía correos reales durante la preparación local.

Antes de exponer el dominio: probar entrega con el proveedor real en un entorno privado, verificar la cuenta operadora y marcar OPERATOR_ACCOUNT_CREATED=true y SMTP_READY=true. Estas marcas son confirmaciones operativas: el validador no prueba la existencia de la cuenta ni realiza un test SMTP. No poner true para saltarse los pasos.

Configurar WEBAPP_URL y NEXTAUTH_URL iguales, con HTTPS y sin subruta ni barra final. Mantener los secretos originales. Para probar con el proveedor real todavía de forma privada, quitar el override bootstrap y acceder por túnel/reverse proxy privado con el dominio configurado.

## Coolify
Importar la carpeta completa desde un repositorio privado como recurso Docker Compose; seleccionar **compose.yaml**. Los archivos authzed-postgres-bootstrap.sh, cube/ y ops/ necesitan sus montajes relativos en el checkout. Introducir las variables del entorno del recurso. No subir .env al repositorio ni publicar la salida completa de `docker compose config`; usar `--quiet` para validar.

Asignar un subdominio HTTPS únicamente al servicio **formbricks**, puerto **3000**. PostgreSQL, Valkey, SpiceDB, Hub, worker y Cube permanecen sin puertos públicos. No crear rutas que expongan Hub directamente: la app proporciona su proxy autenticado. No usar el override bootstrap públicamente ni abrir Mailpit.

Si se migra del Compose manual a Coolify, los volúmenes del proyecto pueden tener otro nombre. No asumir que aparecen los datos: usar el procedimiento de respaldo/restauración y confirmar qué volúmenes administra Coolify. En despliegue manual, al salir del bootstrap detener con ambos archivos antes de recrear solo con compose.yaml, para retirar puertos locales y Mailpit.

## Persistencia y respaldo
Se nombran cuatro volúmenes: postgres (las bases Formbricks y SpiceDB, roles y extensiones), redis (sesiones/colas), uploads y saml (rutas declaradas por la imagen, aunque no se configure SAML). El servicio permissions prepara los volúmenes de la app para UID1001. El respaldo se realiza con todos los servicios de datos detenidos y conserva propietarios numéricos. Ver docs/RESPALDO.md.

Los archivos locales no sustituyen el diseño de almacenamiento remoto: no hay S3/R2 conectado. Validar las cargas de archivos que se vayan a usar antes de ofrecerlas; los formularios incluidos son de texto/selección y no requieren adjuntos. El kit no activa SAML, SSO, whitelabel, permisos avanzados ni otras funciones Enterprise; su disponibilidad depende de la licencia upstream.

## Odoo y oferta de Hefesto
Exportar respuestas desde la interfaz y convertir sus columnas explícitamente a un CSV importable en Odoo CRM. Ver docs/ODOO.md. No se envían datos a Odoo ni se crean oportunidades automáticamente en esta entrega.

Ofrecer instalación, diseño de encuestas, configuración de publicación, integración y mantenimiento según alcance. Mantener créditos y licencias de Formbricks. Los servicios de IA, pagos, contrato/SLA y SMTP no están contratados ni activados por este ZIP.

Kit preparado y revisado localmente; falta la aceptación funcional en servidor. Ver docs/VALIDACION.md. No se ha desplegado una instancia ni creado cuentas o encuestas reales.
