package common

import (
	"context"
	"sync"
	"testing"
)

func TestMetadataStateIsScopedToObligationAndType(t *testing.T) {
	base := WithMetadataProgress(context.Background(), &MetadataProgress{})
	first, cancel := context.WithCancel(base)
	state := MetadataState[int](first, "groups")
	*state = 7
	cancel()
	if MetadataState[int](base, "groups") != state {
		t.Fatal("retry lost state")
	}
	if *MetadataState[int](base, "friends") != 0 {
		t.Fatal("scope leaked")
	}
	if *MetadataState[string](base, "groups") != "" {
		t.Fatal("type leaked")
	}
	fresh := WithMetadataProgress(context.Background(), &MetadataProgress{})
	if *MetadataState[int](fresh, "groups") != 0 {
		t.Fatal("new obligation inherited state")
	}
	plain := context.Background()
	*MetadataState[int](plain, "groups") = 9
	if *MetadataState[int](plain, "groups") != 0 {
		t.Fatal("standalone call inherited state")
	}
	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if MetadataState[int](base, "groups") != state {
				t.Error("concurrent retrieval replaced state")
			}
		}()
	}
	wg.Wait()
}
