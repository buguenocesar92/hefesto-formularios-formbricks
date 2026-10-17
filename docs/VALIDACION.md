# Validación · 2026-10-16
Realizado localmente:
- Sintaxis Python por AST; sintaxis del bootstrap shell con sh -n; parseo YAML; sintaxis del validador Node.
- Ausencia de puertos publicados en Compose base; todas las imágenes fijadas por digest.
- Generación de ocho secretos diferentes, .env 0600, rechazo de sobrescritura y ausencia de marcadores GENERAR pendientes.
- Ejecución real del validador Node: admite bootstrap localhost y rechaza URL insegura/clave inválida/publicación sin completar requisitos.
- Conversor CSV ejecutado con datos ficticios: excluye fila sin consentimiento, conserva columnas Odoo, crea salida 0600 y rechaza sobrescribir.
- Verificador de tar rechaza rutas absolutas, ../, enlaces simbólicos y setuid.
- Con Docker simulado en carpeta temporal: secuencia parada/copia/reinicio; reinicio tras fallo de copia; manifiesto completed solo en copia terminada; rechazo de restauración con servicios activos, volumen ocupado, clave cambiada o configuración alterada; recorrido de restauración sobre archivos tar ficticios.
- Integridad ZIP y exclusión de .env real, respaldos y cachés.

Las pruebas con Docker simulado comprueban lógica de scripts, no ejecutan contenedores, PostgreSQL, Cube, Hub, SpiceDB, SMTP ni la aplicación. No se realizó Docker Compose config con el CLI ni descarga/arranque de las imágenes. No hay prueba visual ni de cifrado/autenticación de Formbricks. No se probó Odoo real ni se conectó Supabase.

Pendiente: docs/ACEPTACION.md completo en servidor de prueba, incluyendo compatibilidad de los digests, migraciones y autorización, entrega SMTP, alta/login/recuperación, publicar/responder/exportar, cargas si se usan, importación Odoo y recuperación real del respaldo frío. No se ha publicado ningún servicio.
