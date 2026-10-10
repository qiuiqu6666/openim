# Migrated group identities

`LegacyGroupConversationMigration` repairs cached `sg_lg_…` conversation entries
after the server has renamed their group to `@lg_…`. Existing OpenIM SDK sync owns
the new groups, memberships, messages and conversations; this module only handles
old local entries that the SDK deliberately retains during incremental sync.

`LegacyGroupConversationProjection` also applies to every first page, refresh and
SDK update batch. Once both exact old/new IDs are present, only the canonical
entry supplies the ordinary list row, unread count and settings. It remembers
replaced IDs for the controller lifetime so late callbacks cannot revive an old
row when the canonical conversation has been hidden. Names are never compared;
unrelated groups and servers are unchanged. The projection only reads metadata;
it neither changes SDK storage nor deletes messages. A unique old draft or an
unsent latest message keeps its recovery entry until the conservative cleanup
below can finish. These entries contain distinct local work, not duplicates.

The original cleanup could leave visually identical rows indefinitely because
reading the old CID's history can require a server fetch after that CID has been
retired. List projection no longer depends on cleanup succeeding. Cleanup keeps
its existing lifecycle and ordering ahead of list reads, so hiding a row cannot
shift the offsets of an in-progress paginated list read.

Cleanup runs from the conversation controller after SDK synchronization and on
refresh. It is restricted to the current migration server, current account/token,
active controller generation and home route. It snapshots every local page before
mutation and requires an authoritative server response showing the new CID exists
and the old CID is absent. The new local conversation must already exist.

Drafts are copied only to an empty replacement draft and verified before hiding
the old entry. Conflicting drafts, pending sends, incomplete history and changed
snapshots are left intact. No message deletion or server-wide clear API is called.
Controller deletion guards keep stale SDK callbacks and cached first pages from
reintroducing hidden entries. Account changes or leaving the home route stop work.

`services/legacy_identity` contains the shared authenticated snapshot transport
and exact legacy group-number normalization used by contact search/profile entry.
An already prefixed ID is never prefixed again; unrelated servers/groups are
unchanged. Physical device migration is required to validate native SDK behavior
beyond the included transport/lifecycle and controller tests.

The large conversation controller retains only lifecycle wiring for this fix;
identity projection and cleanup stay in this directory. Tests cover login's
cached page, refresh when cleanup cannot remove the old row, replacement arriving
after the first page, stale callbacks, restart, unrelated groups, drafts and
pending messages. The existing SDK/GetX list and widgets are reused without theme
changes.
