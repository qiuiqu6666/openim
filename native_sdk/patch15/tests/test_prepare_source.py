import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from prepare_source import digest, receipt, source_files, stage, verify, verify_artifact, verify_dependencies


class SharedSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name) / "project/native_sdk/patch15"
        self.source = self.root / "ios-core-source"
        self.source.mkdir(parents=True)
        self.version = "v3.8.3-patch.15+recovery.13"
        self.mobile = "v0.0.0-20250711185624-d5bb5ecc55c0"
        for name, data in {"go.mod": "require golang.org/x/mobile " + self.mobile,
                           "go.sum": "locked sums", "version/version": self.version,
                           "internal/recovery.go": "package recovery\n"}.items():
            target = self.source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(data, encoding="utf-8")
        (self.root / "core.patch").write_bytes(b"locked patch")
        files = {p.relative_to(self.source).as_posix(): digest(p.read_bytes()) for p in source_files(self.source)}
        self.manifest = {"commit": "base", "sdk_version": self.version, "go_version": "1.24.0",
                         "gomobile": self.mobile, "patch": "core.patch", "patch_sha256": digest(b"locked patch"),
                         "source_directory": "ios-core-source", "source_manifest": "source.json",
                         "source_sha256": digest(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()),
                         "android": {"sdk_version": self.version, "gomobile": self.mobile, "coordinate": "io.openim:core-sdk:recovery.13"},
                         "ios": {"version": self.version, "gomobile": self.mobile}}
        self.snapshot = {k: self.manifest[k] for k in ("commit", "sdk_version", "go_version", "gomobile", "patch_sha256", "source_sha256")}
        self.snapshot["files_sha256"] = files
        self.write_manifest()
        (self.root / "source.json").write_text(json.dumps(self.snapshot), encoding="utf-8")

    def write_manifest(self):
        (self.root / "manifest.json").write_text(json.dumps(self.manifest), encoding="utf-8")

    def test_both_platform_staging_is_identical_and_excludes_runtime_databases(self):
        (self.source / "user.db").write_bytes(b"user runtime data")
        for name in ("ios", "android"):
            destination = self.root / name
            stage(destination, self.root)
            self.assertFalse((destination / "user.db").exists())
            self.assertEqual({p.relative_to(destination).as_posix(): digest(p.read_bytes())
                              for p in source_files(destination)}, self.snapshot["files_sha256"])

    def test_staging_preserves_existing_destination(self):
        with self.assertRaisesRegex(ValueError, "must not exist"):
            stage(self.source, self.root)

    def test_source_edit_is_rejected(self):
        (self.source / "internal/recovery.go").write_text("broken", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "source differs"):
            verify(self.root)

    def test_unlocked_go_file_is_rejected(self):
        (self.source / "internal/extra.go").write_text("package recovery", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "source differs"):
            verify(self.root)

    def test_platform_version_drift_is_rejected(self):
        self.manifest["ios"]["version"] = "old"
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, "versions must match"):
            verify(self.root)

    def test_patch_drift_is_rejected(self):
        (self.root / "core.patch").write_bytes(b"different patch")
        with self.assertRaisesRegex(ValueError, "Patch hash"):
            verify(self.root)

    def test_build_cannot_mutate_dependency_locks(self):
        build = self.root / "build"
        stage(build, self.root)
        (build / "go.mod").write_text("new dependency", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "locked dependencies"):
            verify_dependencies(build, self.snapshot)

    def artifact(self):
        directory = self.root / "artifacts/maven/io/openim/core-sdk/recovery.13"
        directory.mkdir(parents=True)
        name = "core-sdk-recovery.13.aar"
        (directory / name).write_bytes(b"verified build fixture")
        built = receipt(self.manifest, self.snapshot, "android", {name: digest(b"verified build fixture")})
        (directory / "verification.json").write_text(json.dumps(built), encoding="utf-8")
        return directory, built

    def test_matching_artifact_is_accepted(self):
        self.artifact()
        self.assertEqual(verify_artifact("android", self.root)["sdk_version"], self.version)

    def test_old_build_receipt_is_rejected(self):
        directory, built = self.artifact()
        built["source_sha256"] = "old source"
        (directory / "verification.json").write_text(json.dumps(built), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Stale android SDK"):
            verify_artifact("android", self.root)

    def test_replaced_binary_is_rejected(self):
        directory, _ = self.artifact()
        (directory / "core-sdk-recovery.13.aar").write_bytes(b"old binary")
        with self.assertRaisesRegex(ValueError, "artifact hash mismatch"):
            verify_artifact("android", self.root)

    def test_missing_ios_receipt_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Missing ios recovery build receipt"):
            verify_artifact("ios", self.root)

    def ios_artifact(self):
        framework = self.root.parent.parent / "local_plugin/flutter_openim_sdk/ios/Frameworks/OpenIMCore.xcframework"
        names = ("ios-arm64/OpenIMCore.framework/OpenIMCore",
                 "ios-arm64_x86_64-simulator/OpenIMCore.framework/OpenIMCore")
        hashes = {}
        for name in names:
            binary = framework / name
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.write_bytes(("verified iOS build fixture " + name).encode())
            hashes[name] = digest(binary.read_bytes())
        built = receipt(self.manifest, self.snapshot, "ios", hashes)
        evidence = framework.parent / "recovery-verification.json"
        evidence.write_text(json.dumps(built), encoding="utf-8")
        return framework, evidence, built

    def test_matching_ios_receipt_and_binaries_are_accepted(self):
        self.ios_artifact()
        self.assertEqual(verify_artifact("ios", self.root)["sdk_version"], self.version)

    def test_old_ios_source_receipt_is_rejected(self):
        _, evidence, built = self.ios_artifact()
        built["source_sha256"] = "old source"
        evidence.write_text(json.dumps(built), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Stale ios SDK"):
            verify_artifact("ios", self.root)

    def test_ios_receipt_with_missing_simulator_is_rejected(self):
        _, evidence, built = self.ios_artifact()
        del built["binaries_sha256"]["ios-arm64_x86_64-simulator/OpenIMCore.framework/OpenIMCore"]
        evidence.write_text(json.dumps(built), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Incomplete native artifact receipt"):
            verify_artifact("ios", self.root)

    def test_replaced_ios_device_binary_is_rejected(self):
        framework, _, _ = self.ios_artifact()
        (framework / "ios-arm64/OpenIMCore.framework/OpenIMCore").write_bytes(b"old binary")
        with self.assertRaisesRegex(ValueError, "artifact hash mismatch"):
            verify_artifact("ios", self.root)


if __name__ == "__main__":
    unittest.main()
