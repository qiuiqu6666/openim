package interaction

import (
	"context"
	"sync"
	"testing"
	"time"
)

func TestDuplicateResponseDoesNotBlockCleanup(t *testing.T) {
	s := NewWsRespAsyn()
	id, ch := s.AddCh("self")
	first := GeneralWsResp{MsgIncr: id, Data: []byte("first")}
	if err := s.NotifyResp(context.Background(), first); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		done <- s.NotifyResp(context.Background(), GeneralWsResp{MsgIncr: id, Data: []byte("duplicate")})
	}()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("duplicate response should be rejected")
		}
	case <-time.After(time.Second):
		// Unblock the old implementation before failing, so the test leaks no goroutine.
		<-ch
		<-done
		s.DelCh(id)
		t.Fatal("duplicate response blocked the response router and cleanup")
	}
	if got := <-ch; string(got.Data) != "first" {
		t.Fatalf("replaced original response: %s", got.Data)
	}
	s.DelCh(id)
	if err := s.NotifyResp(context.Background(), first); err == nil {
		t.Fatal("late response was accepted")
	}
}

func TestResponseArrivalRacingCleanup(t *testing.T) {
	s := NewWsRespAsyn()
	for i := 0; i < 100; i++ {
		id, _ := s.AddCh("self")
		var wg sync.WaitGroup
		wg.Add(3)
		go func() { defer wg.Done(); _ = s.NotifyResp(context.Background(), GeneralWsResp{MsgIncr: id}) }()
		go func() { defer wg.Done(); _ = s.GetCh(id) }()
		go func() { defer wg.Done(); s.DelCh(id) }()
		wg.Wait()
	}
}
