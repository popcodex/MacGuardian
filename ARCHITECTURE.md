# Arquitectura de MacGuardian 0.2.0

## Núcleo

- `Models.swift`: snapshots de archivos regulares con identidad, propietario, tamaño lógico, bloques, fecha y clasificación.
- `Scanner.swift`: recorrido de solo lectura, exclusiones, incidencias y cancelación; duplicados por tamaño, identidad de inodo, SHA-256 y contenido en bloques.
- `ScanIndex.swift`: totales, categorías, búsquedas y mapa por directorio preparados fuera del actor principal. La vista consulta un índice inmutable, sin recorrer o reordenar el escaneo al actualizar CPU o memoria.
- `Recommendations.swift`: reglas puras y comprobables de recomendación y selección masiva. Los documentos, instaladores, descargas y archivos grandes no se recomiendan solo por edad o tamaño.
- `CleanupEngine.swift`: validación por archivo, coordinación con FileManager, cancelación, movimiento a Papelera y resultado medido. El mover se inyecta en pruebas para operar únicamente sobre fixtures aislados.
- `Safety.swift`: validaciones de alcance, propiedad, exclusiones, enlaces, identidad y preservación de duplicados; historial sincronizado y diario de acciones de solo anexado.
- `SystemInfo.swift`: métricas, parser de ps con rutas absolutas sin espacios de relleno y sin truncamiento de anchura, inventario de aplicaciones y plist.
- `AppRemoval.swift`: validación de propiedad, ubicación, identidad del paquete y ausencia de procesos antes del movimiento.

## Interfaz y concurrencia

La ventana y el ciclo de vida usan AppKit con NSHostingView; la interfaz es SwiftUI. AppModel coordina tareas separadas de prioridad utility y publica resultados en el actor principal. Los procesos se muestrean con intervalo configurable.

Las consultas de archivos usan una clave pequeña (revisión, filtros, búsqueda y orden). Una actualización de métricas no dispara una nueva consulta. Las consultas cancelan resultados obsoletos y solo entregan hasta 1000 filas; Seleccionar todos recorre todos los resultados coincidentes fuera del actor principal, preservando las restricciones.

Las imágenes se cargan fuera de la interfaz, se reducen a miniaturas de 96 píxeles y se almacenan en una caché con límites de cantidad y coste. Se leen iconos propios de paquetes cuando están disponibles; los servicios sin asociación verificable usan un icono genérico. Las tareas de imágenes canceladas no pueden reemplazar iconos más recientes.

El mapa agrupa hijos directos y acumula tamaños durante la indexación. El tamaño lógico, los bloques y las categorías no se recalculan en cada dibujo. La preparación de la hoja de revisión, las exportaciones, el movimiento de archivos y la reconstrucción del índice posterior se realizan en tareas separadas.

## Operaciones de limpieza

El escaneo general retiene hasta 250 000 entradas; el rápido tiene un presupuesto de 100 000 entradas repartidas entre raíces conocidas. No se enumeran carpetas personales para buscar candidatos rápidos.

La limpieza rápida prepara un plan inmutable sin seleccionar uno por uno, pero necesita una autorización explícita antes de modificar. Sus recomendaciones se revalidan frente a procesos activos. No hay vaciado automático de Papelera ni optimizaciones privadas del sistema.

Cada archivo tiene una autorización y un resultado en `history.actions.jsonl`. El archivo se abre sin seguir enlaces, no se aceptan tipos especiales ni enlaces físicos, y el fallo del diario detiene nuevas modificaciones. El historial JSON mantiene las operaciones resumidas para evitar una reescritura completa por archivo.

El informe diferencia bytes lógicos movidos de disponible antes y después. Una variación positiva o negativa del disponible no puede atribuirse exclusivamente a la operación: influyen APFS, la Papelera y otros procesos.

## Aplicaciones

El inventario combina raíces estándar, aplicaciones de macOS visibles, Spotlight, paquetes abiertos y raíces del usuario. Los paquetes anidados no se presentan como aplicaciones independientes. Los componentes internos del sistema ajenos a las raíces elegidas se omiten.

Forzar cierre y desinstalar conserva una identidad del paquete, verifica propiedad y permisos antes de solicitar el cierre a NSRunningApplication, espera confirmación sin bloquear la interfaz y vuelve a comprobar procesos e identidad dentro de la coordinación del movimiento. No se administran servicios privilegiados ni se eliminan los datos asociados.

## Distribución

Swift Package sin dependencias de ejecución externas. El alojamiento AppKit evita los problemas de escenas y toolbar detectados en el entorno de macOS 27. Los scripts compilan Release arm64 y firman fuera de iCloud antes de archivar el paquete.

Los instaladores se guardan en `dist/v<versión>/`, de modo que una entrega no sobrescriba la imagen de otra versión que pueda estar montada. El diseño de Finder se genera sin automatizar su UI, con ds-store y mac-alias únicamente como herramientas de empaquetado.
