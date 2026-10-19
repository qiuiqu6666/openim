# Global text search

Production global text search uses `/msg/search_messages_global` with the current
ordinary user's imToken and `groupByConversation: true`. Only this global-search
entry opts into conversation pagination; callers omitting the flag retain message
pagination. Each result is the latest authorized match for a distinct conversation,
and opening it starts the existing conversation-scoped keyword results page.
The server fills up to the requested number of conversations within its bounded
scan/time budget. A signed, scope-bound cursor tracks emitted conversations;
`hasMore` remains authoritative, and a scope change requires restarting the search.
It no longer enumerates conversations or hydrates SDK
history. Contact/group/conversation-name results retain their existing sources.
The result list keeps server order, shows each matching summary as plain text,
and opens the real chat at the validated HTTP context anchor.

Each query owns its opaque cursor. Empty pages with hasMore=true advance until
results or completion; changed queries discard late responses. Pagination errors
preserve rows and retry the same cursor, while expired cursors reset the search.
There is no total-count claim. Deduplication uses conversationID+seq. All search
HTTP requests share the serialized paced client documented in history_search.

The older GlobalHistoryCloudSearch implementation remains available only through
explicit source/factory injection for compatibility tests. It is not the default
production path and is never an automatic fallback for API failures.
