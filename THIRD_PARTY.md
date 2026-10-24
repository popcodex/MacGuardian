# Dependencias y recursos

MacGuardian.app no integra bibliotecas externas. Usa frameworks distribuidos con macOS. El código de la aplicación, el logotipo y el fondo del instalador se crearon para este proyecto. SF Symbols se utilizan mediante APIs del sistema.

Solo para generar metadatos del instalador:

- ds-store 1.3.3 — MIT — https://github.com/dmgbuild/ds_store
- mac-alias 2.2.3 — MIT — https://github.com/dmgbuild/mac_alias

Se descargaron wheels desde PyPI dentro de `.build/packaging`, sin instalación global. Sus licencias permanecen junto a esas herramientas. No se incluyen en el ejecutable ni en el DMG. El script de diseño utiliza el formato y las APIs documentadas por sus autores; el contenido visual es original.

La investigación de aplicaciones comerciales y proyectos de código disponible figura en Docs/RESEARCH.md. No se incorporó su código, imágenes o interfaces completas.
