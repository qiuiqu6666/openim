# Unified startup and group recovery verification

Version: v3.8.3-patch.15+recovery.53-group-pagination.1

The locked 729-file source retains the previously verified login-cancellation files byte-for-byte and includes joined-group pagination, snapshot validation, resumable metadata and scheduler budget changes.

- Startup / automatic routing / shield / session recovery: 227 passed, 2 skipped.
- Android native bridge: 6 passed. Fixed the JVM-only Android Log mock in the existing dispatch test.
- Core build regression passed. Full SQLite-backed db/group/interaction/conversation/SDK packages passed with CGO enabled.
- Race checks for login cancellation, group pagination and metadata scheduling passed.
- Source lock/build tools: 15 passed.
- Android AAR rebuilt; ARM64 Debug APK built; AAR-to-merged and stripped-to-APK native hashes verified.
- Full Flutter run: +10703 ~231 -243. This is NOT a clean full-suite result. Individual failures are retained in the JSON receipt and full log.
- The full run was stopped on one unrelated Moments lifecycle test waiting for a gated response it releases only after that await. The other 12 tests in that file passed in a separate run excluding the blocked test. No blocked test is counted as passed.
- Full Core run includes unavailable local-server fixtures and tests requiring CGO; relevant database packages were rerun successfully with CGO enabled.
- iOS shares this source lock but still requires an Xcode/macOS framework build and device validation.

Evidence: native_sdk/patch15/verification/recovery.53-startup-merge.json
Full logs: E:/openim/outputs/login-cancel-core/


## 2026-10-24 full-suite remediation

The earlier 243 failures and blocked Moments test above are retained as the original evidence, not the final result. A 243-row ledger records each original failure (67 test files), classification and repair in `E:/openim/outputs/login-cancel-core/failure-ledger.csv` and `.json`.

Attribution is based on source/contract audit against HEAD `2ed67e8c9a0af8d6223b6c0de19bc1fe3e09d56f`: 235 historical defects or stale test contracts; 8 concurrent fund-card style expectation updates. This is not a clean-checkout baseline replay, and does not establish the introducing commit for every failure. No original failure was traced to a new startup routing or Core cancellation defect. See `baseline-evidence.json` for the checked source markers.

Product fixes made during remediation:
- Private history text/voice uses the actual expiry flag; absent countdown text does not mean an unread message expired.
- Detached, cancelled image requests no longer report expected cancellation globally; active listeners still receive failures.
- Returning to latest from distant history no longer treats cached offscreen row geometry as proof that the target is nearby. The keyboard/focus, unseen-message and final-position assertions remain.

The Moments deadlock was in the test: it awaited a second remote settings request behind a gate that it released only after that await. The test now invalidates the owner through the local privacy cache, releases the old response, and verifies that the stale response cannot load the new account or cause an additional request. It runs without exclusion.

Other repairs update shared mocks to the existing unread/connection/group-event interfaces, make assertions match current registration, search, wallet and media behavior, and wait for actual state transitions rather than arbitrary intermediate frames. Album tests retain hung-future and late-result cases; only their injected 40ms real-I/O deadlines become 500ms. Settings shell tests use a deterministic controller; real health-response validation, network invalidation and cancellation remain covered by `test/node_probe_controller_test.dart` and startup tests. Video teardown resumes the paused binding before removing the widget.

No skips or exclusions were added by this remediation. The prior startup refactor's two removed legacy helper test files target APIs that no longer exist; their direct/shield/fallback/late-result behavior is covered by the replacement startup state-machine and native shield preparation tests. They were not removed to resolve these 243 failures.

Core remains recovery.53 with 729 source files and SHA-256 `4ba784cdf2c1f7d68f8c180ad211b12646103c9cab7b4d55a94d178a0b5c3f81`. This remediation revalidated the Android artifact against the lock, passed all 15 source-lock tool tests, and reran `open_im_sdk`, `internal/group`, `internal/interaction`, and `pkg/common` with CGO successfully. Group synchronization and login cancellation source changes are retained. This is not a new iOS build or device/network performance measurement.


Final accepted run: **11,063 passed, 0 failed, 231 existing skipped**, exit 0, **5m17s**, using `flutter test --reporter expanded` with no exclusions. All 67 files containing the original 243 failures are retained in test discovery. The original Moments deadlock test runs and passes.

A fresh isolated checkout also exposed an incomplete sticker HTTP fake: it lacked `connectionTimeout` and `abort`. Both methods were supplied, retaining the successful decode/close-only assertions. This fixture fix is included in the accepted full run.

Concurrent wallet edits produced mixed-source failures in earlier runs (address placement, then text). The final run used `E:/openim/outputs/login-cancel-core/frozen-suite-20261024`. After completion, all 3,373 relevant Dart files matched both the pre-run snapshot and the live workspace, including the wallet changes. There are no outstanding Dart differences in `final-source-consistency.json`; changes made after this receipt naturally require their own validation.

Machine receipt: `native_sdk/patch15/verification/recovery.53-test-remediation.json`.
Accepted log: `E:/openim/outputs/login-cancel-core/full-flutter-remediation-accepted.log`.
Per-failure ledger: `E:/openim/outputs/login-cancel-core/failure-ledger.csv` (243 rows).
