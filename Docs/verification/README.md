# Verificación de la entrega

Este directorio contiene información revisada para publicación:

- `ArtifactIntegrity.json`: hashes de los cinco archivos de la aplicación dentro del DMG y SHA-256 del instalador.
- `Environment.txt`: herramientas y plataforma de validación, sin identificadores de la cuenta local.
- `../../TESTING.md`: alcance de las pruebas, resultados y limitaciones.

Los registros de ejecución detallados permanecen fuera del repositorio público y no se incluyen en el ZIP del proyecto. Los resultados resumidos no afirman pruebas que no se hayan realizado.

## Resultados locales de 0.2.1

- 29 pruebas automatizadas del núcleo aprobadas.
- Compilación Release arm64 y comprobación de firma ad hoc.
- Apertura de la aplicación exacta contenida en el DMG.
- Coincidencia de los cinco archivos del paquete con el archivo firmado.
- Enlace de instalación y fondo del DMG verificados.
- Evaluación de Gatekeeper: rechazo; no hay Developer ID ni notarización.

La versión preliminar conserva las limitaciones descritas en TESTING.md y ROADMAP.md. Una compilación correcta no equivale a notarización ni a validación en todos los equipos.
