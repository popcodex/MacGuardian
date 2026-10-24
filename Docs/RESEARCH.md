# Investigación técnica — 24 de octubre de 2026

Fuentes primarias consultadas en web; no se instalaron ni ejecutaron productos de terceros. Las funciones descritas son las declaradas por sus autores, no una auditoría de sus binarios. Se escribió código original y no se copiaron recursos ni interfaces.

| Referencia | Observación útil | Decisión para MacGuardian / límite |
|---|---|---|
| [CleanMyMac](https://macpaw.com/cleanmymac) | Reúne limpieza, aplicaciones y organización en un panel. | Navegación unificada y revisión explícita; sin promesas de acelerar el Mac, antivirus o puntuación de salud. La edición y permisos limitan funciones. |
| [AppCleaner](https://freemacsoft.net/appcleaner/) | Flujo breve para localizar archivos relacionados a una aplicación. | Mostrar rutas y evidencia antes de actuar. No se reproduce su algoritmo propietario. |
| [DaisyDisk](https://daisydiskapp.com/guide/4/en/) | Mapa navegable, vista previa y documentación específica de espacio oculto, clones, enlaces, iCloud y APFS. | Mapa por directorio y separación entre tamaño lógico y asignado; no se identifica espacio purgable como recuperable garantizado. |
| [OnyX](https://www.titanium-software.fr/en/onyx.html) | Limpieza, mantenimiento, índices y ajustes; requiere versión específica por macOS. | No ejecutar reconstrucciones de bases de datos ni ajustes globales. Consultar herramientas oficiales cuando sea necesario. |
| [Pearcleaner](https://github.com/alienator88/Pearcleaner) | Proyecto de código disponible orientado a desinstalación y restos; licencia fair-code. | Inspiración funcional únicamente. Sin importar su código o recursos. Identificadores exactos, sin borrar por semejanza de nombres. |
| [GrandPerspective](https://grandperspectiv.sourceforge.net/) | Rectángulos proporcionales al tamaño permiten localizar archivos grandes. | Visualización propia proporcional por carpeta, navegación y Finder. No se reutiliza código GPL. |
| [App Cleaner & Uninstaller](https://nektony.com/help/app-cleaner) | Distingue ejecutables, cachés, preferencias, contenedores y servicios. Application Support y Containers pueden contener datos personales. | Conservar datos de aplicación y compartidos por defecto. La desinstalación de servicios privilegiados necesita el fabricante. |
| [DiskCleaner](https://diskcleaner.app/docs/) | Integra almacenamiento, procesos, instaladores y proyectos de desarrollo. | Clasificación contextual de desarrollo; no ejecutar comandos de “optimización” ni borrar entornos o imágenes. No seguir instrucciones para permitir apps globalmente. |
| [Monitor de Actividad](https://support.apple.com/guide/activity-monitor/welcome/mac) | Referencia para CPU, memoria, energía y cierre de procesos. | Explicar semántica de métricas; cerrar solo aplicaciones propias identificadas por macOS; acceso al monitor oficial para métricas no implementadas. |
| [Almacenamiento de macOS](https://support.apple.com/guide/mac-help/optimize-storage-space-sysp4ee93ca4/mac) | Recomendaciones y gestión de almacenamiento desde el sistema. | Priorizar inspección sobre borrado; no gestionar snapshots ni almacenamiento del sistema. |
| [Infall](https://infallmac.com/) | Integra análisis, revisión previa y contextos de desarrollo. | Explicaciones y selección explícita. Sin control de ventiladores ni ajustes privados. |
| [SeeYourDisk](https://seeyourdisk.com/) | La URL no fue accesible mediante la herramienta web. | No se atribuyen características no verificadas. |

## APIs y distribución

- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace): iconos, Finder y apertura de aplicaciones. Apertura de archivos se etiqueta como tal; no se presenta como vista previa sin ejecución.
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice): gestiona helpers de la aplicación, no un interruptor universal para terceros. Se abre `openSystemSettingsLoginItems()`.
- [FileManager.trashItem](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)): mover a Papelera puede fallar por volumen o permisos. No hay sustitución por borrado permanente.
- [Notarización](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution): distribución con Developer ID y notarización requiere identidad/cuenta y conexión al servicio de Apple. Sin identidad en este entorno se usa firma ad hoc local.
- `lstat`, `O_NOFOLLOW`, `host_statistics`, `host_statistics64`, `IOPowerSources`, `ps` y `sysctl`: interfaces del SDK y utilidades incluidas en macOS. Los fallos de acceso se informan como no disponible.

Se revisaron además las declaraciones del SDK local para resolver la ausencia del plugin SwiftUIMacros en Command Line Tools. Un alias explícito usa el property wrapper tradicional `SwiftUI.State<Value>` sin sustituir el framework ni requerir bibliotecas externas.
