# Trabajar en MacGuardian

MacGuardian es un proyecto personal en versión preliminar. Antes de proponer un cambio, consulta ROADMAP.md y SECURITY.md para conocer su alcance y sus restricciones.

## Comunicar un problema

Describe la versión de macOS, la arquitectura, la versión de MacGuardian, los pasos y el resultado esperado. Incluye solo archivos sintéticos o capturas revisadas.

No publiques documentos personales, credenciales, rutas privadas, informes completos de procesos ni volcados de memoria. Si encuentras un problema de seguridad, utiliza el reporte privado de vulnerabilidades del repositorio cuando esté disponible.

## Validar un cambio

- Conserva la separación entre análisis de solo lectura y modificaciones explícitamente autorizadas.
- Usa archivos temporales creados por la prueba. No ejecutes limpiezas, desinstalaciones ni cierres de aplicaciones reales.
- Ejecuta `./Scripts/test.sh` en macOS y documenta cualquier prueba que no puedas realizar.
- Explica los permisos, el comportamiento ante errores y cómo afecta el cambio a las protecciones existentes.
- Mantén los textos de la aplicación en español y actualiza las limitaciones cuando corresponda.

La publicación del código no implica que se haya elegido una licencia de redistribución. El autor aún debe definirla; las licencias de las herramientas externas se documentan por separado en THIRD_PARTY.md.
