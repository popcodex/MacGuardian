# Verificación — 24 de octubre de 2026

## Versión 0.2.0

- **27 pruebas aprobadas, 0 fallos**, conjunto local en 1.698 s. Incluyen recomendaciones conservadoras, selección masiva, cancelación, auditoría, cambios concurrentes y protección de aplicaciones activas.
- Índice y consulta de 50 000 registros sintéticos en segundo plano: 0.810 s en una ejecución; el hilo principal mantuvo su actividad de prueba. No representa un análisis completo del disco.
- Prueba visual con 12 002 archivos sintéticos: seleccionar todos eligió 12 001 y excluyó una base de datos protegida; seleccionar recomendados eligió únicamente un bytecode Python antiguo.
- Se movió exclusivamente ese archivo de prueba a Papelera mediante la interfaz real: un archivo, 26 bytes lógicos, cero errores; el resumen separó el tamaño movido de la variación de espacio libre. No se vació la Papelera.
- Se creó una aplicación desechable propia, se abrió y se probó el cierre forzado y retirada a Papelera. No se cerraron ni desinstalaron aplicaciones personales.
- Limpieza rápida: 2668 entradas examinadas, cero recomendaciones seguras en esa muestra; autorización desactivada correctamente.
- Se verificaron iconos de procesos, inicio automático y desarrollo, navegación y hojas de autorización.
- Muestra puntual en reposo tras navegar: huella física 85.6 MB, máxima 118.3 MB; el hilo principal esperaba eventos. No es un límite garantizado.
- Compilación Release arm64 con firma ad hoc. La compatibilidad con otros equipos y versiones de macOS sigue sin verificarse.

Las siguientes secciones conservan el registro histórico de 0.1.0; sus cantidades y pruebas corresponden a esa versión.


## Entorno observado

- macOS 27.0.1 (26A434), Darwin 27, arm64.
- Modelo leído por la aplicación en ejecución: Mac14,7, Apple M2, 16 GiB físicos (17.18 GB decimales).
- Swift 6.4; Command Line Tools en `/Library/Developer/CommandLineTools`.
- No hay Xcode completo seleccionado: `xcodebuild -version` informa que requiere Xcode.
- `security find-identity -v -p codesigning`: 0 identidades válidas.
- Espacio libre inicial: alrededor de 23 GiB; es variable y depende del contenedor APFS.
- La carpeta del proyecto está en File Provider/iCloud. El entorno de ejecución limita red, procesos, cachés y herramientas de discos; las operaciones de creación/montaje del DMG y la muestra de rendimiento se ejecutaron con autorización adicional de la herramienta.

## Pruebas automáticas ejecutadas

`./Scripts/test.sh`: **11 pruebas aprobadas, 0 fallos**, ejecución del conjunto 1.623 s en la comprobación local previa a la publicación.

1. Escaneo de solo lectura, exclusiones, enlaces simbólicos omitidos y enlaces físicos contados una vez en bloques asignados.
2. Duplicados por tamaño, SHA-256 y contenido; bloqueo de selección de todas las copias.
3. Rechazo de archivo modificado y sustituido por enlace simbólico.
4. Límites correctos de raíces, exclusiones, bases de datos y paquetes protegidos.
5. Límite de entradas y propagación de cancelación.
6. Raíz inexistente informa incidencia.
7. Directorio sin permisos informa incidencia; ancestro simbólico rechazado y normalización léxica de rutas.
8. Si desaparece la copia que se iba a conservar, se bloquea la selección restante.
9. Fixture de 5000 archivos: límite 2000, 2001 entradas visitadas, 1999 archivos retenidos, 0.692 s de escaneo en esa misma ejecución. La carpeta también cuenta como entrada. No representa una medición de todo el disco.
10. Historial persistente con escritura y lectura JSON.
11. Clasificación conservadora de archivos personales y dependencias; bytecode Python antiguo regenerable.

Los fixtures se crean en una carpeta temporal de nombre aleatorio y se destruyen al terminar. No se vació la Papelera ni se borraron documentos del usuario.

## Compilación y distribución

- Debug y Release compilados efectivamente, binario Mach-O arm64.
- `codesign --verify --deep --strict --verbose=2`: aplicación válida en disco y requisito designado satisfecho, incluida la copia montada del instalador.
- Firma ad hoc local; no Developer ID ni notarización. La evaluación explícita de Gatekeeper con `spctl --assess` devolvió **rejected** (código 3); la apertura local de la compilación fue comprobada, pero no se acredita una distribución aceptada por Gatekeeper. No se intentó desactivar Gatekeeper ni eliminar cuarentena.
- `hdiutil verify`: checksum del DMG válido. Hash SHA-256 entregado por separado.
- Se abrió también la aplicación exacta dentro del DMG final, con controles del sistema en español, y se cerró normalmente. El volumen de prueba se expulsó.
- DMG montado en modo de solo lectura para verificar su contenido y apariencia: aplicación, enlace a /Applications, instrucciones, icono y fondo personalizado.
- Se verificó visualmente la presentación en Finder; el diseño depende de la versión de Finder y de sus preferencias.
- No se arrastró la aplicación a /Applications, para no modificar aplicaciones instaladas del usuario.

## Prueba visual y funcional en el Mac

Se abrió la compilación Release mediante la interfaz nativa de macOS y se verificó:

- Ventana redimensionable, tema oscuro, nombre y logo originales, navegación visible sin cabecera recortada.
- Panel con métricas reales: modelo, M2, RAM, almacenamiento, CPU, procesos y aplicaciones. Los contadores varían con el equipo.
- Carpeta sintética fuera de iCloud: cuatro archivos, 110 bytes lógicos, 16 KB asignados y un candidato de caché.
- Mapa de carpetas y listado; la base de datos sintética se presentó como protegida, con selección desactivada.
- Dos archivos idénticos de 30 bytes se agruparon correctamente.
- La hoja de revisión mostró la ruta y consecuencias; el botón de movimiento permaneció desactivado sin autorización. Se canceló sin mover archivos.
- Inventario real de aplicaciones e inicio automático (plist), y monitor de procesos con PID, padre, usuario, CPU y RSS.
- Diagnóstico: presión normal, swap informado por el kernel, batería 80 % y alimentación por corriente en la muestra observada.
- Configuración: modo oscuro seleccionado; el control del monitor de menú se activó y desactivó, dejándolo desactivado.
- Una muestra de 1 segundo del proceso final en reposo informó huella física 32.6 MB (máxima 32.9 MB). Es una muestra puntual, no un límite garantizado durante escaneos.

## Incidencias detectadas y corregidas

- Las cachés del compilador predeterminadas no eran escribibles: se redirigieron al proyecto.
- Command Line Tools no incluía SwiftUIMacros: alias al property wrapper tradicional de State.
- Swift Build no cargaba el complemento de pruebas y añadía metadatos incompatibles con firma: motor nativo y carga explícita de TestingMacros. La firma se realiza en una carpeta temporal fuera de iCloud y luego se archiva el resultado firmado en ZIP, porque la carpeta sincronizada podía reañadir atributos inmediatamente después de limpiarlos; se limpian metadatos únicamente en artefactos generados.
- El motor Swift Build fallaba al generar dSYM en este entorno: Release mediante el motor nativo, sin afirmar disponer de dSYM.
- Escenas/comandos de SwiftUI presentaron recursión y un fallo al abrir en el runtime local: ciclo de vida AppKit con NSHostingView. La barra lateral pasó a composición SwiftUI propia para evitar una superposición de toolbar del sistema.
- Foundation convierte `/private/tmp` en `/tmp` al estandarizar: normalización léxica propia que preserva los componentes comprobados por lstat.
- File Provider marca la carpeta de trabajo como ubicua incluso con archivos locales: se omite y ahora se informa explícitamente como incidencia para no presentar cobertura completa.
- `iconutil` rechazó un iconset de PNG con dimensiones correctas; se empaquetó ICNS con los mismos PNG. `sips` confirmó resolución 1024×1024 y el icono se vio en la aplicación y Finder.

## Lo que no se verificó ni se afirma

- Limpieza real a Papelera, restauración y desinstalación reales: no se ejecutaron sobre datos o aplicaciones del usuario.
- Solicitar cierre o forzar aplicaciones reales: no se hizo.
- Flujo completo de permisos TCC concedidos/denegados mediante diálogo del sistema. Sí se probó denegación POSIX con un fixture.
- Exportación JSON/CSV mediante diálogo de guardado: implementada, sin prueba visual completa del guardado.
- Escaneo completo del disco, 250 000 registros, unidades externas, red, clones/snapshots APFS o carpetas con escritores concurrentes adversarios.
- Compatibilidad de ejecución en macOS 14–26, Intel u otros Macs.
- Notarización y ejecución descargada con cuarentena en otro equipo.

La cobertura pendiente del producto está en ROADMAP.md. Esta entrega no equivale a completar todas las exigencias del prompt maestro.

## Publicación

Los registros detallados de ejecución no se publican ni se incluyen en el archivo del proyecto. Se conserva un resumen revisado y las sumas de integridad del instalador, sin rutas personales. Las imágenes del repositorio muestran la aplicación real; los listados de archivos usan únicamente fixtures sintéticos.
