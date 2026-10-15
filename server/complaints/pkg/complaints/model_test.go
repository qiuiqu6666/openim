package complaints

import (
	"github.com/google/uuid"
	"strings"
	"testing"
)

func TestComplaintValidation(t *testing.T) {
	base := Payload{ClientRequestID: uuid.NewString(), ReportedUserID: "peer", Reason: "spam"}
	for _, kind := range []string{"c2c", "group"} {
		p := base
		if kind == "group" {
			p.GroupID = "group"
			p.ReportedUserID = ""
		}
		if _, e := Normalize(p, kind, "owner"); e != nil {
			t.Fatal(e)
		}
	}
	cases := []struct {
		name, kind string
		edit       func(*Payload)
	}{
		{"self", "c2c", func(p *Payload) { p.ReportedUserID = "owner" }},
		{"no peer", "c2c", func(p *Payload) { p.ReportedUserID = "" }},
		{"invalid reason", "c2c", func(p *Payload) { p.Reason = "invalid" }},
		{"no group", "group", func(p *Payload) {}},
		{"invalid request", "c2c", func(p *Payload) { p.ClientRequestID = "../unsafe" }},
		{"long content", "c2c", func(p *Payload) { p.Content = strings.Repeat("中", 2001) }},
		{"wrong route", "bad", func(p *Payload) {}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			p := base
			tc.edit(&p)
			if _, e := Normalize(p, tc.kind, "owner"); e == nil {
				t.Fatal("invalid complaint accepted")
			}
		})
	}
	base.Content = strings.Repeat("中", 2000)
	if _, e := Normalize(base, "c2c", "owner"); e != nil {
		t.Fatal(e)
	}
}
func TestRequestDigestIncludesEvidence(t *testing.T) {
	p := Payload{ClientRequestID: uuid.NewString(), Reason: "fraud"}
	d := Digest(p, "c2c", []string{"a"})
	if d != Digest(p, "c2c", []string{"a"}) {
		t.Fatal("unstable digest")
	}
	if d == Digest(p, "c2c", []string{"b"}) || d == Digest(p, "group", []string{"a"}) {
		t.Fatal("evidence or chat type ignored")
	}
	p.Content = "edited"
	if d == Digest(p, "c2c", []string{"a"}) {
		t.Fatal("edited content ignored")
	}
}
func TestStatuses(t *testing.T) {
	for _, s := range []string{"received", "processing", "resolved", "rejected"} {
		if !ValidStatus(s) {
			t.Fatal(s)
		}
	}
	if ValidStatus("deleted") {
		t.Fatal("unsupported status accepted")
	}
}
