#!/usr/bin/env python3
"""Record verified native binaries against the locked shared Core source."""
import argparse
import json
import pathlib
import plistlib
import zipfile

from prepare_source import digest, receipt, verify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("ios", "android"))
    parser.add_argument("artifact", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    manifest, snapshot, _ = verify()
    version = manifest["sdk_version"].encode()
    hashes = {}
    if args.platform == "android":
        with zipfile.ZipFile(args.artifact) as archive:
            for abi in manifest["android"]["abis"]:
                binary = archive.read(f"jni/{abi}/libgojni.so")
                if version not in binary:
                    raise ValueError(f"Missing Core version in Android {abi}")
        hashes[args.artifact.name] = digest(args.artifact.read_bytes())
    else:
        info = plistlib.loads((args.artifact / "Info.plist").read_bytes())
        architectures = set()
        for library in info["AvailableLibraries"]:
            if library["SupportedPlatform"] != "ios":
                raise ValueError("Unexpected Framework platform")
            variant = library.get("SupportedPlatformVariant", "device")
            architectures.update((variant, arch) for arch in library["SupportedArchitectures"])
            name = library["LibraryIdentifier"] + "/" + library["LibraryPath"] + "/OpenIMCore"
            binary = (args.artifact / name).read_bytes()
            if version not in binary:
                raise ValueError("Missing Core version in " + name)
            hashes[name] = digest(binary)
        if architectures != {("device", "arm64"), ("simulator", "arm64"), ("simulator", "x86_64")}:
            raise ValueError("Framework must contain device arm64 and simulator arm64/x86_64")
    args.output.write_text(json.dumps(receipt(manifest, snapshot, args.platform, hashes), indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
