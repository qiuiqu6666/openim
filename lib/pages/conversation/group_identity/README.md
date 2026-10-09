# Migrated group identities

`LegacyGroupConversationMigration` repairs cached `sg_lg_…` conversation entries
after the server has renamed their group to `@lg_…`. Existing OpenIM SDK sync owns
the new groups, memberships, messages and conversations; this module only handles
old local entries that the SDK deliberately retains during incremental sync.

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
