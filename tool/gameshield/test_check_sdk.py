import io
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

from check_sdk import archive_symbols, check_android, check_ios, digest_files


def elf(alignment):
    data = bytearray(120)
    data[:7] = b'\x7fELF\x02\x01\x01'
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, 1)
    struct.pack_into('<I', data, 64, 1)
    struct.pack_into('<Q', data, 112, alignment)
    return data


def member(name, data):
    name_bytes = name.encode()
    payload = name_bytes + data
    header = (f'#1/{len(name_bytes)}'.ljust(16) + '0'.ljust(12) + '0'.ljust(6) +
              '0'.ljust(6) + '100644'.ljust(8) + str(len(payload)).ljust(10) + '`\n').encode()
    return header + payload + (b'\n' if len(payload) % 2 else b'')


def archive(cpu, platform, symbols):
    strings, entries = b'', b''
    for symbol in symbols:
        entries += struct.pack('<II', len(strings), 0)
        strings += symbol.encode() + b'\0'
    table = struct.pack('<I', len(entries)) + entries + struct.pack('<I', len(strings)) + strings
    obj = struct.pack('<IIIIIIII', 0xfeedfacf, cpu, 0, 1, 1, 24, 0, 0)
    obj += struct.pack('<IIIIII', 0x32, 24, platform, 15 << 16, 15 << 16, 0)
    return b'!<arch>\n' + member('__.SYMDEF', table) + member('fixture.o', obj)


def fat(blobs):
    offset = 8 + 20 * len(blobs)
    headers, payloads = b'', b''
    for cpu, blob in blobs:
        headers += struct.pack('>IIIII', cpu, 0, offset, len(blob), 0)
        payloads += blob
        offset += len(blob)
    return struct.pack('>II', 0xcafebabe, len(blobs)) + headers + payloads


class SDKInspectionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def aar(self, old_classes=False, library='libgameshieldjni.so', alignment=16384):
        jar = io.BytesIO()
        with zipfile.ZipFile(jar, 'w') as archive:
            for name in ('Mobile', 'Client'):
                archive.writestr(f'com/gameshield/sdk/mobile/{name}.class', b'fixture')
            if old_classes:
                archive.writestr('go/Seq.class', b'fixture')
        path = self.root / 'sdk.aar'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('classes.jar', jar.getvalue())
            for abi in ('armeabi-v7a', 'arm64-v8a', 'x86_64'):
                archive.writestr(f'jni/{abi}/{library}', elf(alignment))
        return path

    def xcframework(self, minimum='15.0', old_symbols=False, simulator_platform=7):
        root = self.root / 'GameShieldSDK.xcframework'
        libraries = []
        symbols = ['_MobileVersion', '_MobileNewClientWithToken']
        if old_symbols:
            symbols += ['_go_seq_inc_ref', '_OBJC_CLASS_$_GoSeqRef', '_crosscall2']
        for name, variant in [('ios-arm64', None), ('ios-arm64_x86_64-simulator', 'simulator')]:
            framework = root / name / 'GameShieldSDK.framework'
            framework.mkdir(parents=True)
            (framework / 'Info.plist').write_bytes(plistlib.dumps({
                'CFBundleExecutable': 'GameShieldSDK', 'MinimumOSVersion': minimum}))
            blobs = [(0x100000c, archive(0x100000c, simulator_platform if variant else 2, symbols))]
            if variant:
                blobs += [(0x1000007, archive(0x1000007, simulator_platform, symbols))]
            (framework / 'GameShieldSDK').write_bytes(fat(blobs))
            item = {'LibraryIdentifier': name, 'LibraryPath': 'GameShieldSDK.framework',
                    'SupportedPlatform': 'ios'}
            if variant:
                item['SupportedPlatformVariant'] = variant
            libraries.append(item)
        (root / 'Info.plist').write_bytes(plistlib.dumps({'AvailableLibraries': libraries}))
        return root

    def test_android_accepts_isolated_names_and_16kb(self):
        self.assertEqual(check_android(self.aar())[0], [])

    def test_android_rejects_duplicate_go_classes(self):
        errors, _ = check_android(self.aar(old_classes=True))
        self.assertTrue(any('go.*' in error for error in errors))

    def test_android_rejects_same_library_name_even_when_aligned(self):
        errors, _ = check_android(self.aar(library='libgojni.so'))
        self.assertTrue(any('name conflicts' in error for error in errors))

    def test_android_rejects_4kb_even_after_renaming(self):
        errors, _ = check_android(self.aar(alignment=4096))
        self.assertTrue(any('16KB' in error for error in errors))

    def test_ios_accepts_isolated_symbol_index_and_both_platforms(self):
        self.assertEqual(check_ios(self.xcframework())[0], [])

    def test_ios_rejects_runtime_symbols_even_with_correct_metadata(self):
        errors, _ = check_ios(self.xcframework(old_symbols=True))
        self.assertTrue(any('unisolated' in error for error in errors))

    def test_ios_rejects_metadata_version_100(self):
        errors, _ = check_ios(self.xcframework(minimum='100.0'))
        self.assertTrue(any('MinimumOSVersion 100.0' in error for error in errors))

    def test_ios_rejects_device_objects_in_simulator_slice(self):
        errors, _ = check_ios(self.xcframework(simulator_platform=2))
        self.assertTrue(any('object platform' in error for error in errors))

    def test_archive_without_symbol_index_is_not_accepted(self):
        with self.assertRaises(ValueError):
            archive_symbols(b'!<arch>\n')

    def test_receipt_hash_changes_if_vendor_binary_changes(self):
        root = self.xcframework()
        before = digest_files(root)
        binary = root / 'ios-arm64/GameShieldSDK.framework/GameShieldSDK'
        binary.write_bytes(binary.read_bytes() + b'changed')
        self.assertNotEqual(before, digest_files(root))
        json.dumps(digest_files(root))


if __name__ == '__main__':
    unittest.main()
