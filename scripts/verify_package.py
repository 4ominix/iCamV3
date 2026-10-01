#!/usr/bin/env python3
import pathlib, plistlib, sys
root,control=map(pathlib.Path,sys.argv[1:3])
required=['Applications/iCamV3App.app/Info.plist','Applications/iCamV3App.app/iCamV3App',
 'Library/MobileSubstrate/DynamicLibraries/iCamV3.dylib','Library/MobileSubstrate/DynamicLibraries/iCamV3.plist',
 'Library/MobileSubstrate/DynamicLibraries/iCamV3Controls.dylib','Library/MobileSubstrate/DynamicLibraries/iCamV3Controls.plist']
for rel in required:
    p=root/rel
    if not p.is_file() or not p.stat().st_size: raise SystemExit('Missing packaged file: '+rel)
info=plistlib.loads((root/required[0]).read_bytes())
if info.get('CFBundleExecutable')!='iCamV3App' or info.get('CFBundleIdentifier')!='com.icamv3.app':
    raise SystemExit('Invalid packaged app identity')
for name in ['preinst','postinst','prerm']:
    p=control/name
    if not p.is_file():raise SystemExit('Missing maintainer script: '+name)
post=(control/'postinst').read_text()
for line in ['APP_PATH="/Applications/iCamV3App.app"','SHARED_DIR="/var/mobile/Library/iCamV3"','chown mobile:mobile "$SHARED_DIR"']:
    if line not in post:raise SystemExit('Packaged postinst missing: '+line)
print('PASS: extracted controller app, both tweaks, bundle metadata and RootHide maintainer paths')
