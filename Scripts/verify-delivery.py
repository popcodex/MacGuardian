#!/usr/bin/env python3
"""Compare the signed archive with a read-only mounted installer supplied by caller."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import os
import plistlib
import sys
root = Path(__file__).resolve().parent.parent
mount = Path(sys.argv[1])
version = plistlib.loads((root / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
artifacts = Path(os.environ.get('MACGUARDIAN_OUTPUT_DIR', str(root / 'dist' / ('v' + version))))
with ZipFile(artifacts / 'MacGuardian-app.zip') as archive:
    expected = {n: hashlib.sha256(archive.read(n)).hexdigest() for n in archive.namelist() if not n.endswith('/') and n.startswith('MacGuardian.app/')}
actual = {'MacGuardian.app/' + str(p.relative_to(mount / 'MacGuardian.app')): hashlib.sha256(p.read_bytes()).hexdigest() for p in (mount / 'MacGuardian.app').rglob('*') if p.is_file()}
assert expected == actual, 'El contenido del DMG no coincide con el archivo firmado'
assert os.readlink(mount / 'Aplicaciones') == '/Applications'
assert (mount / '.background/background.png').read_bytes() == (root / 'Resources/InstallerBackground.png').read_bytes()
report = {'version': version, 'architecture': 'arm64', 'filesMatchSignedArchive': True, 'applicationFiles': actual, 'applicationsLink': '/Applications', 'backgroundMatches': True, 'dmgSHA256': hashlib.sha256((artifacts / 'MacGuardian.dmg').read_bytes()).hexdigest()}
output = root / 'Docs/verification/ArtifactIntegrity.json'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print('Integridad verificada:', len(actual), 'archivos; enlace y fondo coinciden.')
print('SHA-256 del DMG:', report['dmgSHA256'])
