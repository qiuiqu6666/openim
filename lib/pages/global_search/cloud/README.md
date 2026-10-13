# Global message history supplementation

The global history category first shows local keyword results, then calls
`GlobalHistoryCloudSearch`. Each interaction discovers at most 50 SDK
conversations and hydrates at most three conversations, one 100-message history
page each. Subsequent interactions rotate through the remaining conversations
and older cursors. This includes SDK conversations outside the home list's
currently rendered window. It does not discover deleted/unauthorized chats.

`getAdvancedHistoryMessageList` delegates missing-history retrieval and local
storage to OpenIM; the client does not invent a cloud keyword-search endpoint.
After hydration, global local search runs again and replaces the result groups,
avoiding duplicate appended results. An explicit continuation remains while
any conversation history or conversation-list page is unfinished. Server
retention and the account's history permissions remain authoritative.

Each keyword search owns its scan. Query changes, disposal, account changes and
token changes invalidate results and stop subsequent requests. Native requests
already submitted can finish caching. Errors retain retryable cursors and the
previous results. Contact/group/name searches retain their existing sources.

Single-conversation keyword, sender, date, media, voice and file results use the
shared `chat/history_search/cloud` path. The calendar allows cloud-capable dates
even if its local availability probe has no messages; hydration occurs in the
selected date's result page, not once for every calendar cell.
