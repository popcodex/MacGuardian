# Cobertura y pendientes del prompt maestro

0.1.0 es una primera versión funcional. No se declara completo el producto solicitado.

| Módulo | Implementado | Pendiente / límite |
|---|---|---|
| Inicio | Equipo, sistema, volumen, CPU entre muestras, memoria, contadores de inventarios, análisis explícito | Análisis rápido de varias raíces en una sesión; no se crea puntuación de salud |
| Almacenamiento | Escaneo autorizado, categorías, tamaños, fechas, búsqueda, mapa proporcional navegable, Finder, incidencias y cancelación | Treemap completo multinivel; paquetes y nube omitidos; sin análisis del espacio exclusivo de clones/snapshots |
| Limpieza | Cachés, logs antiguos, instaladores, comprimidos y desarrollo, revisión individual, Papelera, exclusiones | No vacía Papelera, no limpia temporales globales ni cachés de navegador activas; no hay garantías de regeneración general |
| Aplicaciones | Icono, versión, bundle ID, ejecución, tamaño analizado, datos asociados por ID exacto, mover paquete cerrado de usuario a Papelera | Desarrollador por firma, última ejecución fiable, Group Containers por entitlements, desinstalación profunda selectiva, restos con evidencia histórica y desinstaladores oficiales detectados |
| Procesos | PID, padre, usuario, CPU de ps, RSS, tiempo, estado, ruta, reglas descriptivas, cierre de NSRunningApplication con confirmación | Energía, atribución completa de servicios a aplicaciones, detección de supervivencia tras cierre; no se cierran procesos arbitrarios |
| Inicio automático | Inventario parcial plist y apertura de ajustes oficiales | Inventario público completo de Login Items no disponible mediante SMAppService; no se afirma estado de carga ni impacto sin medición |
| Duplicados | Tamaño, SHA-256, contenido en bloques, deduplicación por inodo, preservar copia | Vista previa Quick Look integrada y tratamiento de clones por bloques exclusivos; no se comparan fotos similares |
| Desarrollo | Cachés pip/npm/Homebrew, DerivedData, pycache, dependencias/entornos y Docker protegidos cuando aparecen en el alcance | Inventarios específicos de gestores, simuladores obsoletos y Docker mediante sus herramientas; purgas individuales autorizadas |
| Diagnóstico | CPU, memoria definida, swap, presión cuando el kernel la expone, volumen, carga y alimentación | Tasas de disco/red, ciclos y salud de batería, energía por proceso; acceso a Monitor de Actividad como alternativa |
| Historial | Registro local atómico de análisis, autorizaciones, movimientos, solicitudes de cierre y errores | SQLite, retención y restauración integrada sin sobrescritura |
| Configuración | Apariencia oscuro/claro/sistema, exclusiones, intervalo, menú opcional | Atajos configurables y selección múltiple de raíces |
| Informes | JSON y CSV reales | PDF |
| Distribución | Script Release arm64 y DMG con identidad visual original | Developer ID y notarización requieren identidad válida; compatibilidad con otros macOS y equipos por validar |

Prioridades siguientes: validación manual completa de operaciones con fixtures y permisos TCC; eliminar la ventana residual de cambios de rutas tanto como permitan las APIs de Papelera; medir rendimiento de árboles grandes; pruebas en macOS 14–26 y otros volúmenes; desinstalación profunda con revisión de datos compartidos.
