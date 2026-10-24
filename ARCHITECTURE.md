# Arquitectura

## Capas

- `MacGuardianCore/Models.swift`: snapshots inmutables de archivos (`lstat`), categorías y semántica de tamaños; ningún dato ficticio.
- `Scanner.swift`: recorrido incremental de solo lectura, exclusiones, cancelación y límite de entradas. Duplicados por tamaño, identidad de inodo, SHA-256 en bloques de 1 MiB y comparación final.
- `Safety.swift`: pertenencia al alcance, rutas protegidas, enlaces, propiedad y revalidación de snapshots. Historial JSON local con escritura atómica.
- `SystemInfo.swift`: métricas públicas del kernel, IOPowerSources, inventario de aplicaciones y plist; utilidades del sistema con ejecutable fijo y argumentos separados. Sin shell.
- `MacGuardian/AppModel.swift`: estado observable, coordinación de tareas, inventarios, exportación, autorización separada y acciones registradas.
- `MacGuardianApp.swift`, `ModuleViews.swift`: ventana y barra de menús AppKit con NSHostingView para SwiftUI, navegación de once secciones, ventanas redimensionables, revisión antes de actuar y Finder.

## Concurrencia y recursos

Escaneo, hashing, inventarios y consultas de métricas se ejecutan en tareas de prioridad utility fuera del actor principal. Los resultados y avances regresan al actor principal. Solo hay un escaneo o comparación por vez; la cancelación se propaga a la tarea separada. No hay demonios, launch agents, bucles ocultos ni servicios privilegiados. El muestreo existe mientras la aplicación está abierta; su intervalo es configurable.

El escáner retiene como máximo 250 000 registros y 200 incidencias detalladas. El contador de incidencias adicionales se preserva. El listado visual está limitado a 3000 registros por filtro; la exportación preserva el resultado completo. No se cargan archivos completos para calcular hashes.

La interacción con Papelera usa NSFileCoordinator y revalidación inmediata. Las acciones y persistencia se realizan en el actor principal en esta versión; los lotes grandes pueden generar pausas, por lo que no hay selección masiva automática. El historial JSON debe migrarse a almacenamiento indexado si aumenta mucho su volumen.

## Distribución

Swift Package sin dependencias. `Scripts/build.sh` genera Release arm64 y arma y firma la estructura `.app` con Info.plist e ICNS en una carpeta temporal fuera de iCloud, antes de archivarla en un ZIP dentro de dist. El empaquetador extrae ese ZIP en una carpeta temporal para evitar que File Provider añada metadatos a la aplicación firmada. Usa el motor nativo de SwiftPM para evitar un fallo verificado de dsymutil en el entorno restringido. `Scripts/package-dmg.sh` crea DMG con aplicación, enlace a Aplicaciones, icono de volumen y fondo original; Un script escribe .DS_Store usando ds-store y mac-alias solo como herramientas de empaquetado. No utiliza automatización de Finder.

`Scripts/Artwork.swift` dibuja icono y fondo con AppKit; `Resources/Logo.svg` conserva un original vectorial editable. Ningún recurso de otras marcas fue incorporado.

## Decisiones deliberadas

No se instala un helper privilegiado. No se edita launchd. No se accede a bases de datos privadas de Login Items. No se infiere la propiedad de archivos por similitud de nombres. La firma de desarrolladores de terceros no se presenta como verificada. La búsqueda de datos asociados usa únicamente coincidencias exactas del identificador de paquete y conserva todos los resultados.

El ciclo de vida usa NSApplicationDelegate en vez de escenas SwiftUI: se verificó un fallo y un bucle de actualización al combinar las escenas y comandos en el runtime macOS 27 de este equipo. El alojamiento AppKit permitió abrir y operar la interfaz.
