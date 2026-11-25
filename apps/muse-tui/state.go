package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// state is remembered between runs in ~/.config/muse-tui/state.json.
type state struct {
	Group   int     `json:"group"`
	Sort    int     `json:"sort"`
	Vis     int     `json:"vis"`
	Volume  float64 `json:"volume"`
	Shuffle bool    `json:"shuffle"`
	Repeat  int     `json:"repeat"`
}

func statePath() string {
	cfg, _ := os.UserConfigDir()
	return filepath.Join(cfg, "muse-tui", "state.json")
}

func loadState() state {
	var st state
	if b, err := os.ReadFile(statePath()); err == nil {
		_ = json.Unmarshal(b, &st)
	}
	if st.Group < 0 || st.Sort < 0 || st.Vis < 0 || st.Repeat < 0 {
		st = state{}
	}
	return st
}

func saveState(st state) {
	p := statePath()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return
	}
	if b, err := json.MarshalIndent(st, "", "  "); err == nil {
		_ = os.WriteFile(p, b, 0o644)
	}
}
