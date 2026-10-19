package model_struct

// One database read transaction. Coverage is derived from these rows, never
// from a separately committed boolean or the syncer's delivery checkpoint.
type MessageWindowRead struct {
	Conversation *LocalConversation
	Rows         []*LocalChatLog
}
