"""Inspect GameShield binaries before optional staging. Python standard library only.

These structural checks do not replace coexistence tests with OpenIM on devices.
No credentials are accepted or printed by this tool.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import plistlib
import shutil
import struct
import sys
import zipfile


def is_within(path, root):
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def elf_alignments(data):
    if data[:4] != b'\x7fELF' or data[5] != 1:
        raise ValueError('Expected a little-endian ELF library')
    if data[4] == 2:
        offset = struct.unpack_from('<Q', data, 32)[0]
        size, count = struct.unpack_from('<HH', data, 54)
        alignment_offset, fmt = 48, '<Q'
    elif data[4] == 1:
        offset = struct.unpack_from('<I', data, 28)[0]
        size, count = struct.unpack_from('<HH', data, 42)
        alignment_offset, fmt = 28, '<I'
    else:
        raise ValueError('Unsupported ELF word size')
    return [struct.unpack_from(fmt, data, offset + index * size + alignment_offset)[0]
            for index in range(count)
            if struct.unpack_from('<I', data, offset + index * size)[0] == 1]


def archive_members(data):
    if data[:8] != b'!<arch>\n':
        raise ValueError('Expected a static archive, not a renamed dynamic library')
    position = 8
    while position + 60 <= len(data):
        header = data[position:position + 60]
        if header[58:60] != b'`\n':
            raise ValueError('Malformed archive member')
        name = header[:16].decode('ascii').strip()
        size = int(header[48:58].decode('ascii').strip())
        member = data[position + 60:position + 60 + size]
        if len(member) != size:
            raise ValueError('Truncated archive')
        if name.startswith('#1/'):
            length = int(name[3:])
            name = member[:length].rstrip(b'\0').decode('ascii')
            member = member[length:]
        yield name, member
        position += 60 + size
        position += position % 2


def archive_symbols(data):
    for name, member in archive_members(data):
        if 'SYMDEF' not in name:
            continue
        wide = '_64' in name
        step, fmt = (8, '<Q') if wide else (4, '<I')
        table_size = struct.unpack_from(fmt, member)[0]
        string_position = step + table_size
        string_size = struct.unpack_from(fmt, member, string_position)[0]
        strings = member[string_position + step:string_position + step + string_size]
        if len(strings) != string_size or table_size % (2 * step):
            raise ValueError('Malformed archive symbol table')
        result = set()
        for offset in range(step, step + table_size, 2 * step):
            index = struct.unpack_from(fmt, member, offset)[0]
            if index >= len(strings):
                raise ValueError('Invalid archive symbol index')
            result.add(strings[index:].split(b'\0', 1)[0].decode('utf-8'))
        return result
    raise ValueError('Archive has no defined-symbol index')


def slices(data):
    magic = struct.unpack_from('>I', data)[0]
    if magic not in (0xcafebabe, 0xcafebabf):
        yield None, data
        return
    count = struct.unpack_from('>I', data, 4)[0]
    if count > 16:
        raise ValueError('Unexpected architecture count')
    for index in range(count):
        if magic == 0xcafebabe:
            cpu, _, offset, size, _ = struct.unpack_from('>IIIII', data, 8 + 20 * index)
        else:
            cpu, _, offset, size, _, _ = struct.unpack_from('>IIQQII', data, 8 + 32 * index)
        value = data[offset:offset + size]
        if len(value) != size:
            raise ValueError('Truncated architecture slice')
        yield cpu, value


def object_versions(data):
    for _, member in archive_members(data):
        if member[:4] != b'\xcf\xfa\xed\xfe':
            continue
        cpu = struct.unpack_from('<I', member, 4)[0]
        count = struct.unpack_from('<I', member, 16)[0]
        position = 32
        for _ in range(count):
            command, size = struct.unpack_from('<II', member, position)
            if size < 8 or position + size > len(member):
                raise ValueError('Malformed Mach-O load command')
            if command == 0x32:
                platform, version = struct.unpack_from('<II', member, position + 8)
                yield cpu, platform, version >> 16
            elif command == 0x25:
                version = struct.unpack_from('<I', member, position + 8)[0]
                yield cpu, None, version >> 16
            position += size


def check_android(path):
    errors, details = [], []
    with zipfile.ZipFile(path) as aar:
        with zipfile.ZipFile(io.BytesIO(aar.read('classes.jar'))) as classes:
            names = classes.namelist()
        collisions = [name for name in names if name.startswith('go/') and name.endswith('.class')]
        if collisions:
            errors.append(f'{len(collisions)} unisolated go.* classes conflict with OpenIM')
        for api in ('Mobile', 'Client'):
            if f'com/gameshield/sdk/mobile/{api}.class' not in names:
                errors.append(f'Missing compatible public Java API: {api}')
        libraries = [name for name in aar.namelist() if name.startswith('jni/') and name.endswith('.so')]
        abis = {name.split('/')[1] for name in libraries}
        for abi in ('arm64-v8a', 'armeabi-v7a', 'x86_64'):
            if abi not in abis:
                errors.append(f'Missing Android architecture: {abi}')
        for name in libraries:
            if name.endswith('/libgojni.so'):
                errors.append(f'{name}: native library name conflicts with OpenIM')
            alignment = elf_alignments(aar.read(name))
            details.append(f'{name}: PT_LOAD alignments {alignment}')
            if not alignment or any(value < 16384 or value % 16384 for value in alignment):
                errors.append(f'{name}: requires 16KB ELF alignment')
    return errors, details


def check_ios(path):
    errors, details = [], []
    info = plistlib.loads((path / 'Info.plist').read_bytes())
    variants = set()
    for library in info['AvailableLibraries']:
        variant = library.get('SupportedPlatformVariant', 'device')
        variants.add(variant)
        if library.get('SupportedPlatform') != 'ios':
            errors.append('Unexpected non-iOS framework variant')
        framework = path / library['LibraryIdentifier'] / library['LibraryPath']
        if not is_within(framework.resolve(), path.resolve()):
            raise ValueError('Framework metadata escapes SDK directory')
        metadata = plistlib.loads((framework / 'Info.plist').read_bytes())
        minimum = metadata.get('MinimumOSVersion', '')
        try:
            major = int(minimum.split('.')[0])
            if major < 1 or major > 15:
                errors.append(f'{variant}: invalid or unsupported MinimumOSVersion {minimum}')
        except ValueError:
            errors.append(f'{variant}: missing valid MinimumOSVersion')
        binary = framework / metadata['CFBundleExecutable']
        if not is_within(binary.resolve(), framework.resolve()):
            raise ValueError('Binary metadata escapes framework directory')
        observed = set()
        for cpu, archive in slices(binary.read_bytes()):
            symbols = archive_symbols(archive)
            conflicts = sorted(symbol for symbol in symbols if symbol.startswith((
                '_go_seq_', '_x_cgo_', '_cgo_', '_crosscall2', '_x_crosscall2',
                '_OBJC_CLASS_$_GoSeqRef', '_OBJC_METACLASS_$_GoSeqRef',
                '_OBJC_CLASS_$_Universeerror', '_OBJC_METACLASS_$_Universeerror')))
            if conflicts:
                errors.append(f'{variant}: {len(conflicts)} unisolated gomobile symbols, e.g. {conflicts[:4]}')
            for api in ('_MobileNewClientWithToken', '_MobileVersion'):
                if api not in symbols:
                    errors.append(f'{variant}: missing public Objective-C API {api}')
            versions = list(object_versions(archive))
            if not versions:
                errors.append(f'{variant}: no inspectable Mach-O platform information')
            for object_cpu, platform, version in versions:
                observed.add(object_cpu)
                if cpu is not None and object_cpu != cpu:
                    errors.append(f'{variant}: architecture slice contains a different CPU')
                expected_platform = 7 if variant == 'simulator' else 2
                if platform not in (None, expected_platform) or version > 15:
                    errors.append(f'{variant}: object platform/minimum OS is incompatible')
            details.append(f'{variant}: {len(symbols)} indexed definitions; {len(versions)} Mach-O version records')
        expected = {0x100000c, 0x1000007} if variant == 'simulator' else {0x100000c}
        if observed != expected:
            errors.append(f'{variant}: architecture set differs from {sorted(expected)}')
    if variants != {'device', 'simulator'}:
        errors.append('Both device and simulator variants are required')
    return sorted(set(errors)), details


def digest_files(root):
    result = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError('SDK staging does not accept symbolic links')
        if path.is_file() and path.name != 'compatibility.json':
            result[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def stage(path, platform):
    project = Path(__file__).resolve().parents[2]
    target = project / 'local_plugin/gameshield_bridge/vendor' / platform
    # Leave existing artifacts intact; replacement requires a fresh inspection.
    if target.exists():
        raise ValueError(f'Staging directory already exists: {target}')
    target.mkdir(parents=True)
    if platform == 'android':
        shutil.copy2(path, target / 'GameShieldSDK.aar')
    else:
        shutil.copytree(path, target / 'GameShieldSDK.xcframework')
    staged_path = target / ('GameShieldSDK.aar' if platform == 'android' else 'GameShieldSDK.xcframework')
    errors, _ = (check_android if platform == 'android' else check_ios)(staged_path)
    if errors:
        raise ValueError('The copied SDK failed inspection. No compatibility receipt was created.')
    receipt = {'schema': 1, 'platform': platform, 'compatible': True,
               'files': digest_files(target), 'requires_device_coexistence_test': True}
    (target / 'compatibility.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(f'Staged structurally compatible SDK: {target}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=['android', 'ios'])
    parser.add_argument('path', type=Path, help='AAR file or XCFramework directory')
    parser.add_argument('--stage', action='store_true', help='Stage only if every structural check passes')
    args = parser.parse_args()
    try:
        path = args.path.resolve(strict=True)
        if args.platform == 'ios' and any(item.is_symlink() for item in path.rglob('*')):
            raise ValueError('SDK contains symbolic links')
        errors, details = (check_android if args.platform == 'android' else check_ios)(path)
        for detail in details:
            print(detail)
        for error in errors:
            print(f'FAIL: {error}')
        if errors:
            print('Not staged. Ask the SDK vendor for an OpenIM-compatible build.')
            return 1
        print('Structural checks passed; device coexistence and live network tests remain required.')
        if args.stage:
            stage(path, args.platform)
        return 0
    except (OSError, ValueError, KeyError, struct.error, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f'Inspection failed: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
