#!/usr/bin/env python3
"""Verify and stage the same locked Core source for both native builds."""
import argparse
import hashlib
import json
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def source_files(source):
    # Tests can leave SQLite/log files behind. They are never build inputs.
    return sorted(p for p in source.rglob("*") if p.is_file()
                  and not any(x in {".git", ".gitnexus", "__pycache__", "logs"}
                              for x in p.relative_to(source).parts)
                  and not any(x in p.name for x in (".db", ".sqlite", ".log")))


def verify(root=ROOT):
    manifest = read_json(root / "manifest.json")
    snapshot = read_json(root / manifest["source_manifest"])
    source = root / manifest["source_directory"]
    for field in ("commit", "sdk_version", "go_version", "gomobile", "patch_sha256"):
        if snapshot[field] != manifest[field]:
            raise ValueError(f"Source/manifest mismatch: {field}")
    if manifest["android"]["sdk_version"] != manifest["sdk_version"] or manifest["ios"]["version"] != manifest["sdk_version"]:
        raise ValueError("Android and iOS SDK versions must match")
    if manifest["android"]["gomobile"] != manifest["gomobile"] or manifest["ios"]["gomobile"] != manifest["gomobile"]:
        raise ValueError("Android and iOS gomobile versions must match")
    if digest((root / manifest["patch"]).read_bytes()) != manifest["patch_sha256"]:
        raise ValueError("Patch hash mismatch")
    actual = {p.relative_to(source).as_posix(): digest(p.read_bytes()) for p in source_files(source)}
    if actual != snapshot["files_sha256"]:
        changed = sorted(k for k in actual.keys() | snapshot["files_sha256"].keys()
                         if actual.get(k) != snapshot["files_sha256"].get(k))
        raise ValueError("Core source differs from lock: " + ", ".join(changed[:12]))
    tree_hash = digest(json.dumps(actual, sort_keys=True, separators=(",", ":")).encode())
    if tree_hash != snapshot["source_sha256"] or tree_hash != manifest["source_sha256"]:
        raise ValueError("Source tree hash mismatch")
    mod = (source / "go.mod").read_text()
    if "golang.org/x/mobile " + manifest["gomobile"] not in mod:
        raise ValueError("gomobile differs from go.mod")
    if (source / "version/version").read_text().strip() != manifest["sdk_version"]:
        raise ValueError("Embedded source version differs from release")
    return manifest, snapshot, source


def stage(output, root=ROOT):
    manifest, snapshot, source = verify(root)
    if output.exists():
        raise ValueError("Build source destination must not exist; existing files preserved")
    output.mkdir(parents=True)
    for name in snapshot["files_sha256"]:
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, destination)
    return manifest, snapshot


def verify_dependencies(source, snapshot):
    for name in ("go.mod", "go.sum"):
        if digest((source / name).read_bytes()) != snapshot["files_sha256"][name]:
            raise ValueError("Build changed locked dependencies: " + name)


def receipt(manifest, snapshot, platform, binaries):
    return {"platform": platform, "commit": manifest["commit"],
            "sdk_version": manifest["sdk_version"], "source_sha256": snapshot["source_sha256"],
            "patch_sha256": manifest["patch_sha256"], "go_version": manifest["go_version"],
            "gomobile": manifest["gomobile"], "core_tests": "passed",
            "device_runtime": "not tested", "binaries_sha256": binaries}


def verify_artifact(platform, root=ROOT):
    manifest, snapshot, _ = verify(root)
    if platform == "android":
        version = manifest["android"]["coordinate"].split(":")[2]
        directory = root / "artifacts/maven/io/openim/core-sdk" / version
        evidence = directory / "verification.json"
        expected = {"core-sdk-" + version + ".aar"}
    else:
        directory = root.parent.parent / "local_plugin/flutter_openim_sdk/ios/Frameworks/OpenIMCore.xcframework"
        evidence = directory.parent / "recovery-verification.json"
        expected = {"ios-arm64/OpenIMCore.framework/OpenIMCore",
                    "ios-arm64_x86_64-simulator/OpenIMCore.framework/OpenIMCore"}
    if not evidence.is_file():
        raise ValueError(f"Missing {platform} recovery build receipt; run native_sdk/patch15/build-{platform}." + ("sh" if platform == "ios" else "ps1"))
    built = read_json(evidence)
    for field in ("sdk_version", "commit", "source_sha256", "patch_sha256", "go_version", "gomobile"):
        if built.get(field) != manifest[field]:
            raise ValueError(f"Stale {platform} SDK ({field}); rebuild from the current shared Core")
    if built.get("platform") != platform or set(built.get("binaries_sha256", {})) != expected:
        raise ValueError("Incomplete native artifact receipt")
    for name, expected_hash in built["binaries_sha256"].items():
        if digest((directory / name).read_bytes()) != expected_hash:
            raise ValueError("Native artifact hash mismatch: " + name)
    return built


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--check-dependencies", type=pathlib.Path)
    parser.add_argument("--check-artifact", choices=("android", "ios"))
    args = parser.parse_args()
    manifest, snapshot, _ = verify()
    if args.output:
        stage(args.output)
    if args.check_dependencies:
        verify_dependencies(args.check_dependencies, snapshot)
    if args.check_artifact:
        verify_artifact(args.check_artifact)
    print(json.dumps({"sdk_version": manifest["sdk_version"],
                      "source_sha256": snapshot["source_sha256"],
                      "files": len(snapshot["files_sha256"])}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        sys.exit(str(error))
