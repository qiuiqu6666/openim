# GameShield native bridge

Optional local Flutter plugin for GameShield 60.1.10. The public channel is `openim/gameshield` with `start`, `status`, and `stop`. Both native implementations own their client per Flutter engine and serialize lifecycle operations on a worker queue; channel replies return on the main thread. Native exception messages and license tokens are not forwarded into logs or error details.

The plugin builds without the vendor SDK. Android accesses its optional public Java API reflectively; iOS conditionally compiles the adapter when `GameShieldSDK` can be imported. Vendor artifacts require a matching compatibility receipt and are excluded from version control.

See [the app integration guide](../../lib/core/gameshield/README.md) for checks, installation, configuration, current scope, and the outstanding device verification. Structural inspection is a prerequisite, not a guarantee of Go runtime coexistence.
