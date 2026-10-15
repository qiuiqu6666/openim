package sdk_params_callback

// Version 1 is additive to the existing history wire format. A local window
// is current relative to locally known bounds, not a claim of server freshness.
type MessageWindow struct {
	Version          int        `json:"version"`
	ConversationID   string     `json:"conversationID"`
	TargetWatermark  int64      `json:"targetWatermark"`
	LatestServerSeq  int64      `json:"latestServerSeq"`
	LowerBound       int64      `json:"lowerBound"`
	Covered          [][2]int64 `json:"covered"`
	Missing          [][2]int64 `json:"missing"`
	Source           string     `json:"source"`
	Readiness        string     `json:"readiness"`
	CoverageStatus   string     `json:"coverageStatus"`
	Publishable      bool       `json:"publishable"`
	EmptyConfirmed   bool       `json:"emptyConfirmed"`
	VisibilityKey    string     `json:"visibilityKey"`
	SnapshotRevision string     `json:"snapshotRevision"`
}
