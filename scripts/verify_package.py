#!/usr/bin/env python3
"""Check exactly one signed Mach-O slice's extracted entitlements plist."""
import pathlib
import plistlib
import sys
from xml.parsers.expat import ExpatError

REQUIRED = (
    'platform-application',
    'com.apple.private.security.no-sandbox',
    'com.apple.private.security.storage.AppBundles',
    'com.apple.private.security.storage.AppDataContainers',
)


def verify(path):
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ValueError(f'Cannot read entitlements {path}: {error}') from error
    if not data.strip():
        raise ValueError(f'Empty entitlements output: {path}; check ldid and the signed slice')
    try:
        entitlements = plistlib.loads(data)
    except (ValueError, ExpatError, plistlib.InvalidFileException) as error:
        raise ValueError(
            f'Invalid entitlements plist {path}: {error}. '
            'Extract arm64 and arm64e separately with lipo -thin before ldid -e; '
            'concatenated XML documents are not one plist.'
        ) from error
    if not isinstance(entitlements, dict):
        raise ValueError(f'Entitlements root must be a dictionary: {path}')
    for key in REQUIRED:
        if entitlements.get(key) is not True:
            raise ValueError(f'Signed executable missing entitlement: {key} ({path})')


def main(argv):
    if len(argv) != 1:
        print('Usage: verify_entitlements.py <single-slice-entitlements.plist>', file=sys.stderr)
        return 2
    path = pathlib.Path(argv[0])
    try:
        verify(path)
    except ValueError as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 1
    print(f'PASS: signed app contains required RootHide storage entitlements ({path.name})')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
