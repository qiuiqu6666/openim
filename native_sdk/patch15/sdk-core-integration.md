# sdk-core integration — 2026-10-19

Integrated `origin/sdk-core` commit `09ed4707f1ec8a79551a880265dc397a1f73c4fc` into the client’s existing `core-source` boundary. The branch is a standalone Go repository without shared client history, so it is integrated as source rather than merged into the client root.

Runtime identity: `v3.8.3-patch.15+recovery.39-group-offline.3`.

The integration adds bounded member batches, retained metadata progress across busy retries, and resumable friend profiles. Existing client upload deadlines and cancellable hash locks in `internal/third/file` are retained; the SDK branch still carries an older upload implementation. Existing client-only files remain in place. The cumulative patch and shared source lock are updated together. The existing cold-receipt test retains its locked CRLF bytes; patch replay differs only in those line endings and the three declared build overlays.

Verification evidence: `verification/recovery.39-group-offline.3-ios.json`. Core and SQLite tests, group/syncer tests, 15 source tooling tests, and group/common/relation/interaction race tests passed. Both iOS slices were built and verified. Release app `3.0.1+2032` was built without signing and checked for the integrated runtime version. Device behavior and Android artifacts are not verified for this revision; Android metadata explicitly marks its binaries stale.
