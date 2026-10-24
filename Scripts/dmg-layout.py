#!/usr/bin/env python3
"""Write Finder metadata for the project's own mounted installer volume."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / '.build' / 'packaging'))
from ds_store import DSStore
from mac_alias import Alias
mount = Path(sys.argv[1]).resolve()
background = Alias.for_file(str(mount / '.background' / 'background.png')).to_bytes()
with DSStore.open(str(mount / '.DS_Store'), 'w+') as store:
    store['.']['vSrn'] = ('long', 1)
    store['.']['icvl'] = ('type', b'icnv')
    store['.']['bwsp'] = {
        'ShowStatusBar': False, 'ShowTabView': False, 'ShowToolbar': False,
        'ShowPathbar': False, 'ShowSidebar': False, 'SidebarWidth': 0,
        'WindowBounds': '{{120, 120}, {790, 560}}', 'ContainerShowSidebar': False,
        'PreviewPaneVisibility': False,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundColorRed': 0.035, 'backgroundColorGreen': 0.055, 'backgroundColorBlue': 0.09, 'scrollPositionX': 0.0, 'scrollPositionY': 0.0, 'backgroundType': 2, 'backgroundImageAlias': background,
        'iconSize': 96.0, 'textSize': 13.0, 'gridSpacing': 100.0,
        'gridOffsetX': 0.0, 'gridOffsetY': 0.0, 'labelOnBottom': True,
        'showItemInfo': False, 'showIconPreview': True, 'arrangeBy': 'none',
    }
    store['.']['vstl'] = ('type', b'icnv')
    store['MacGuardian.app']['Iloc'] = (210, 245)
    store['Aplicaciones']['Iloc'] = (545, 245)
    store['LEEME.txt']['Iloc'] = (680, 355)
print('Diseño Finder escrito en', mount / '.DS_Store')
