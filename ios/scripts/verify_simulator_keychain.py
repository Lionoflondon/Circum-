#!/usr/bin/env python3
"""Fail QA early if a simulator app cannot persist Firebase Auth in Keychain.

Simulator entitlements must be embedded by Xcode in the executable. Adding
restricted iOS entitlements to an ad-hoc codesign signature is not sufficient.
"""
import plistlib
import struct
import sys
from pathlib import Path


def embedded_entitlements(binary):
    if binary[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected a thin arm64 simulator executable')
    commands = struct.unpack_from('<I', binary, 16)[0]
    cursor = 32
    for _ in range(commands):
        command, length = struct.unpack_from('<II', binary, cursor)
        if command == 0x19:  # LC_SEGMENT_64
            count = struct.unpack_from('<I', binary, cursor + 64)[0]
            for i in range(count):
                section = cursor + 72 + i * 80
                name, segment, _, size, offset = struct.unpack_from(
                    '<16s16sQQI', binary, section)
                if name.rstrip(b'\0') == b'__entitlements' and segment.rstrip(b'\0') == b'__TEXT':
                    return plistlib.loads(binary[offset:offset + size].rstrip(b'\0'))
        cursor += length
    raise ValueError('Missing Xcode simulator entitlements; rebuild with signing enabled')


def main():
    app = Path(sys.argv[1])
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if 'iPhoneSimulator' not in info.get('CFBundleSupportedPlatforms', []):
        raise ValueError('This check is for simulator artifacts only')
    if info['CFBundleIdentifier'] != 'com.circum.app':
        raise ValueError('Expected the Sender app')
    entitlements = embedded_entitlements((app / info['CFBundleExecutable']).read_bytes())
    identifier = entitlements.get('application-identifier', '')
    groups = entitlements.get('keychain-access-groups', [])
    if not identifier.endswith('.com.circum.app') or groups != [identifier]:
        raise ValueError('Sender requires exactly its own resolved Keychain access group')
    print('PASS: Sender simulator embeds its own isolated Keychain access group')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, IndexError, OSError) as error:
        sys.exit(str(error))
