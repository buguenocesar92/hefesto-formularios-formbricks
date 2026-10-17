# Traspaso mediante CSV a Odoo CRM
1. Exportar respuestas de una encuesta de captación desde Formbricks y revisar el encabezado real. El formato y nombres dependen de las preguntas/versión.
2. Indicar explícitamente las columnas que contienen nombre, correo, mensaje y consentimiento. Ejemplo con el CSV ficticio incluido:

```sh
python3 scripts/export_to_odoo.py examples/respuestas-demo.csv oportunidades.csv --name-column Nombre --email-column Correo --message-column Mensaje --consent-column Contacto
```

3. El script omite filas sin aceptación reconocida (sí/si/yes/true/1) o sin correo con @. No verifica titularidad ni validez real del correo. Produce name, contact_name, email_from y description; conserva el origen y rechaza sobrescribir la salida. Ante valores que podrían interpretarse como fórmula en una planilla, antepone apóstrofo; revisar cómo desea conservarlos el cliente.
4. En Odoo, importar en CRM → oportunidades y mapear campos según idioma y versión. Hacer primero la prueba de importación y revisar duplicados. El conversor no asigna empresa, vendedor, equipo, etapa, etiquetas ni registros externos y no deduplica oportunidades. No importarlo repetidamente sin un criterio de actualización.
5. Revisar un lote ficticio antes del real. El script no usa credenciales Odoo ni hace solicitudes de red. El CSV generado contiene datos personales: guardarlo con acceso restringido y retirarlo cuando termine el proceso acordado.

Una futura integración automática por webhook/API necesitaría autenticación, validación de firma, mapeo de IDs, idempotencia y política de reintentos. No se incluye como si ya estuviera instalada.
