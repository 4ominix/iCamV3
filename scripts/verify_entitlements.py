#!/usr/bin/env python3
import plistlib, sys
with open(sys.argv[1],'rb') as f:e=plistlib.load(f)
for key in ['platform-application','com.apple.private.security.no-sandbox',
            'com.apple.private.security.storage.AppBundles','com.apple.private.security.storage.AppDataContainers']:
    if e.get(key) is not True:raise SystemExit('Signed executable missing entitlement: '+key)
print('PASS: signed app contains required RootHide storage entitlements')
