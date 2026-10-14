# Contact display data

`ContactRemarkSource` is the read-only contract for friend remarks in conversation
previews, notifications, calls and group member labels. Its declaration lives in
`openim_common/lib/src/contacts/`; this directory preserves the app import entry.
`HomeBinding` exposes the existing
`ContactsLogic` directory through this contract; it creates no second contact
cache, SDK listener or request path.

`remarkFor` reads the reactive directory in constant time. Confirmed local edits,
SDK friend changes/deletions and initial directory loading update the same source.
The source rejects a closed or changed account/session. Notification policy
receives only the resolved remark so anonymous and private previews keep their
existing privacy rules. Shared call widgets depend only on the common contract,
never on application controllers. `ContactNameBuilder` rebuilds existing name and
avatar layouts when the directory changes, without mutating SDK or stored names.

Group member search may obtain remark-matching contact IDs from this directory;
the group module verifies their actual membership before displaying them.

Coverage: `test/pages/conversation/widgets/conversation_sender_remark_test.dart`,
`test/pages/contacts/contacts_logic_test.dart`, and `test/core/notifications/`.
