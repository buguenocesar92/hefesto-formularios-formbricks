# Respaldo frío y recuperación
## Copiar
`python3 scripts/backup.py`

El script registra qué servicios de larga duración estaban activos, detiene todo el stack de datos con 120 segundos de gracia, comprueba que ya no figuran en ejecución, comprime postgres, redis, uploads y saml y copia configuración + .env. Escribe manifiesto completed y hashes solo al terminar. Reinicia los servicios previamente activos incluso si el respaldo falla. Mailpit no contiene datos productivos y no se copia.

No ejecutar durante una migración, inicialización, despliegue o con otros procesos que monten esos volúmenes. Hay indisponibilidad durante toda la copia; reservar ventana de mantenimiento y espacio suficiente. Los servicios auxiliares de otras instalaciones no deben usar estos volúmenes. Revisar que PostgreSQL cerró limpiamente en logs y completar un ensayo de recuperación.

`python3 scripts/check_backup.py /ruta/respaldo` comprueba producto/versión, hashes y rutas de tar, rechazando enlaces, dispositivos, rutas de escape, duplicados y modos setuid/setgid. Límite de este kit: 2 millones de entradas y 500 GiB expandidos por volumen. Los hashes no prueban autenticidad; usar solo copias de confianza.

El respaldo contiene datos personales, respuestas, roles, sesiones, colas, claves y configuración. Guardarlo cifrado fuera del VPS con acceso restringido, retención acordada y prueba periódica de recuperación. No incluye las imágenes Docker, DNS, TLS de Coolify ni datos de servicios externos/S3. Para recuperación sin registro disponible, archivar aparte las imágenes y su arquitectura.

## Recuperar sin sobrescribir
1. Usar otro servidor compatible con la misma arquitectura y esta misma versión de imágenes, kit y PostgreSQL18. Esta es una copia física de volúmenes, no un dump portable entre versiones mayores/arquitecturas. No actualizar el motor durante una restauración.
2. Descomprimir el kit en carpeta nueva. Copiar de forma privada .env del respaldo, conservando todos los secretos; cambiar COMPOSE_PROJECT_NAME a un nombre único, por ejemplo hefesto-formularios-ensayo. No ejecutar configure.py sobre un entorno recuperado. Para comparar el kit, el script exige configuración/código idénticos a los respaldados excepto .env.
3. No arrancar servicios todavía. Confirmar proyecto distinto y volúmenes nuevos/vacíos. El script rechaza servicios activos o cualquier volumen con contenido y nunca borra un volumen existente.
4. Ejecutar `python3 scripts/restore.py /ruta/respaldo --accept-restored-jobs`. Verifica todos los archivos, conserva propietarios/permisos y restaura los cuatro volúmenes. No arranca el stack automáticamente. Si falla una extracción, dejar el destino como fallido y repetir en volúmenes nuevos tras investigar; no extraer encima parcialmente.
5. Primer ensayo aislado:

```sh
docker compose -f compose.yaml -f compose.bootstrap.yaml -f compose.rehearsal.yaml up -d
```

La red internal bloquea la salida de contenedores y Mailpit captura el correo. Puede ser necesario haber descargado previamente las imágenes. Las tareas/webhooks restaurados pueden intentar ejecutarse: no quitar el aislamiento ni usarlo como producción hasta revisar colas y destinos. Los puertos de prueba se usan por túnel SSH.
6. Probar login, autorización, encuestas, respuestas ficticias y exportación. Confirmar la misma clave ENCRYPTION_KEY, las claves de sesión/API y ambas claves DB: el script rechaza claves cambiadas. Los enlaces, sesiones y tareas del respaldo pueden reaparecer; acordar su tratamiento antes de promover una recuperación.
7. Para producción, revisar dominio, SMTP, colas y autorizaciones en un cambio controlado. No conectar el ensayo a clientes reales. La configuración del proxy y DNS se recupera por separado.

Un volcado lógico hacia Supabase sería otro procedimiento y no lo realiza este script.
