package common

import "context"

type preparedRecoveryMetadataKey struct{}

// Set only after the conversation/visibility and read-watermark receipt. The
// marker belongs to this recovery attempt, never a global timestamp cache.
func WithPreparedRecoveryMetadata(ctx context.Context) context.Context {
	return context.WithValue(ctx, preparedRecoveryMetadataKey{}, true)
}

func RecoveryMetadataPrepared(ctx context.Context) bool {
	ready, _ := ctx.Value(preparedRecoveryMetadataKey{}).(bool)
	return ready
}
