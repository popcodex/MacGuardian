# Seguridad y recuperación

El análisis es de solo lectura. No hay limpieza al iniciar, al cerrar, programada u oculta. Las operaciones autorizadas se ejecutan fuera del hilo de la interfaz. No hay borrado permanente ni comandos de purga. No se modifica SIP, Gatekeeper, servicios ni preferencias críticas. No se solicitan credenciales administrativas.

## Movimiento de archivos a Papelera

- Selección inicialmente vacía y revisión de nombre, ruta, tamaño, clasificación, motivo y recuperación.
- Autorización explícita: casilla para la selección manual; en Inicio, pulsar LIMPIEZA RÁPIDA autoriza la selección y el movimiento automático de los recomendados.
- Solo archivos regulares del alcance del análisis o del plan rápido y del usuario actual.
- Exclusiones y rutas críticas se validan otra vez antes de actuar. Se rechazan paquetes de aplicación, fototecas, .git, bases de datos y ubicaciones sensibles identificadas.
- Rechazo de enlaces simbólicos en el archivo y en todos sus ancestros. Enlaces físicos con más de un nombre quedan bloqueados.
- Se compara inodo, dispositivo, tamaño, fecha precisa y clasificación con el snapshot. Un archivo cambiado debe volver a analizarse.
- Duplicados: se bloquea seleccionar todas las copias; debe existir al menos una copia no seleccionada y sin cambios.
- Coordinación con NSFileCoordinator para aplicaciones que respetan el protocolo. Validación inmediatamente antes de `trashItem`.
- Registro de autorización antes de modificar; si no puede registrarse, no se inicia la modificación. Éxitos y errores se registran individualmente, incluyendo destino en Papelera cuando macOS lo devuelve.
- No existe sustitución por `removeItem` cuando falla la Papelera. `removeItem` solo se utiliza en pruebas para destruir sus propios fixtures.

Recuperación: Finder → Papelera → elemento → Sacar de la papelera, mientras siga allí. El historial informa rutas; no ofrece una restauración automática que pueda sobrescribir datos nuevos. La Papelera puede no estar disponible en ciertos volúmenes.

## Aplicaciones y procesos

La eliminación de una aplicación conserva todos los archivos asociados. Se admiten paquetes dentro de /Applications, ~/Applications o carpetas adicionales autorizadas, propiedad del usuario, sin ancestros simbólicos, fuera de exclusiones y con identidad comprobada. Antes de moverlos se comprueba que no queden procesos asociados. Se bloquean paquetes Apple y MacGuardian. No se gestionan controladores ni servicios: utiliza el desinstalador oficial.

Solo se solicita cierre a `NSRunningApplication` de usuario actual y ejecutable bajo ubicaciones de aplicaciones permitidas, revalidando PID, usuario y ruta. No se envían señales a PIDs arbitrarios. Forzar cierre exige confirmación y puede perder cambios sin guardar. Para desinstalar después, se espera la finalización y se revalidan identidad, propiedad y procesos; si no se puede confirmar, se detiene la operación.

## Límites del modelo de seguridad

Esta herramienta de usuario no es una frontera de seguridad frente a un proceso malicioso de la misma cuenta. Las APIs de Papelera reciben rutas: existe una ventana residual entre la comprobación y el movimiento si otro proceso sustituye componentes sin cooperar con NSFileCoordinator. No se garantiza atomicidad frente a adversarios. Cierra las aplicaciones responsables y vuelve a analizar si cambian archivos. No la utilices para modificar árboles compartidos con escritores no confiables.

Las reglas de clasificación son conservadoras pero no pueden probar que cualquier archivo sea prescindible. Verde significa bytecode regenerable identificado y antiguo, no permiso automático para eliminarlo. La autorización de usuario sigue siendo obligatoria. No se intenta vaciar cachés activas, detectar malware ni manipular bases de datos.

Sin App Sandbox en esta compilación local; los límites de macOS/TCC y la política interna siguen aplicándose. Sin conexión de red iniciada por MacGuardian. Abrir un documento mediante su aplicación puede ejecutar esa aplicación; el botón se etiqueta explícitamente como abrir y no se hace durante un análisis.

## Firma

La firma ad hoc comprueba integridad local; no acredita una identidad Developer ID ni notarización. No ofrece la misma experiencia Gatekeeper que una distribución firmada por Apple. No se elimina la cuarentena ni se recomienda desactivar controles globales.

## Comunicar una vulnerabilidad

No publiques datos personales ni instrucciones para afectar sistemas reales en un issue. Si está habilitado, utiliza **Security → Report a vulnerability** para comunicar el problema de forma privada. Incluye la versión y una reproducción con fixtures sintéticos; no adjuntes credenciales, documentos ni volcados de memoria del usuario.

## Selección masiva y limpieza rápida

Seleccionar todos incluye archivos personales cuando están dentro del filtro de Almacenamiento: no es una recomendación de borrado. Siempre se revisa y autoriza por separado. Se excluyen archivos protegidos, ajenos, enlaces físicos, paquetes y exclusiones. Si ya hay grupos de duplicados comparados se conserva una copia.

Seleccionar recomendados no se basa únicamente en tamaño o antigüedad. Solo usa bytecode Python antiguo o raíces reconocidas de cachés pip, npm, Homebrew y Xcode, así como informes .ips/.crash antiguos dentro de los diagnósticos del usuario. Se conserva lo reciente, protegido o vinculado a herramientas activas. Sin inventario fiable de procesos no se proponen recomendaciones. Los datos regenerables pueden requerir descargas o nuevas compilaciones más lentas.

La pulsación del botón LIMPIEZA RÁPIDA autoriza el flujo completo: análisis, selección automática y movimiento de los recomendados a Papelera, sin confirmación intermedia. No vacía la Papelera. Puede no encontrar nada recomendable: no se inventan candidatos ni resultados. El registro por archivo usa anexado con O_NOFOLLOW/O_NONBLOCK y rechaza enlaces físicos y tipos especiales. Si no se puede escribir, no se avanza a otros archivos.
