# Migrated group identities

Existing OpenIM SDK sync owns groups, memberships, messages and conversations
renamed from `lg_…` to `@lg_…`. This module projects old local entries that the SDK
deliberately retains during incremental sync into the canonical conversation list.

`LegacyGroupConversationProjection` also applies to every first page, refresh and
SDK update batch. Once both exact old/new IDs are present, only the canonical
entry supplies the ordinary list row, unread count and settings. It remembers
replaced IDs for the controller lifetime so late callbacks cannot revive an old
row when the canonical conversation has been hidden. Names are never compared;
unrelated groups and servers are unchanged. The projection only reads metadata;
it neither changes SDK storage nor deletes messages. A unique old draft or an
unsent latest message keeps its recovery entry until the conservative cleanup
below can finish. These entries contain distinct local work, not duplicates.

Read-only identity normalization recognizes both the original migration IP and
the current built-in HTTPS endpoint `99imapi.99chat.vip`. Config's endpoint
migration must not disable alias projection on login or refresh. Recognition of
that domain does not expand `LegacyServerSnapshot.allowedServer`, so it grants no
additional permission for automatic destructive cleanup.

Reading the retired CID's history can trigger server gap-filling and extensive
SDK logs. Waiting for every history page before publishing the list caused login
and refresh to stall. Automatic `LegacyGroupConversationMigration` is therefore
disconnected from the controller, including SDK synchronization callbacks. Login,
refresh and live updates use only the read-only projection; they do not request
old group history, copy SDK drafts or physically hide group aliases.

The standalone migration helper remains available with its conservative checks
for separately controlled maintenance, but no application route invokes it.
It requires the current migration server, account/token, active caller, a complete
local snapshot and authoritative confirmation of the replacement CID.

Drafts are copied only to an empty replacement draft and verified before hiding
the old entry. Conflicting drafts, pending sends, incomplete history and changed
snapshots are left intact. No message deletion or server-wide clear API is called.
Controller projection keeps stale SDK callbacks from reintroducing duplicate
rows. Account changes and controller disposal reset projection state.

`services/legacy_identity` contains the shared authenticated snapshot transport
and exact legacy group-number normalization used by contact search/profile entry.
An already prefixed ID is never prefixed again; unrelated servers/groups are
unchanged. Physical device migration is required to validate native SDK behavior
beyond the included transport/lifecycle and controller tests.

The large conversation controller retains only projection wiring for this fix;
identity projection and cleanup stay in this directory. Tests cover login's
cached page, refresh when cleanup cannot remove the old row, replacement arriving
after the first page, stale callbacks, restart, unrelated groups, drafts and
pending messages, and verifies that list reads never invoke group-history or
group-hide APIs. The existing SDK/GetX list and widgets are reused without theme
changes.
