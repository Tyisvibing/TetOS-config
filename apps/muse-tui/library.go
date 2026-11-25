package main

// Reads Muse's library database (read-only) through the sqlite3 CLI, so no cgo/SQLite driver is needed.

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

type Track struct {
	ID       int64   `json:"id"`
	Path     string  `json:"path"`
	Title    string  `json:"title"`
	Artist   string  `json:"artist"`
	Album    string  `json:"album"`
	Genre    string  `json:"genre"`
	Year     int     `json:"year"`
	Duration float64 `json:"duration"`
	AddedAt  int64   `json:"added_at"`
}

func (t Track) titleOrFile() string {
	if t.Title != "" {
		return t.Title
	}
	return strings.TrimSuffix(filepath.Base(t.Path), filepath.Ext(t.Path))
}

func (t Track) Display() string {
	title := t.titleOrFile()
	if t.Artist != "" && !strings.HasPrefix(t.Artist, "Unknown") {
		return t.Artist + " - " + title
	}
	return title
}

// Source is one selectable list of tracks (all songs, a playlist, a genre).
type Source struct {
	Name   string
	Kind   string  // all | playlist | smart | genre | artist | album
	Orig   []Track // library / playlist order
	Tracks []Track // Orig with the current sort applied
}

func defaultDB() string {
	if p := os.Getenv("MUSE_DB"); p != "" {
		return p
	}
	cfg, _ := os.UserConfigDir()
	return filepath.Join(cfg, "muse-player", "library.db")
}

func query(db, sql string) ([]byte, error) {
	cmd := exec.Command("sqlite3", "-readonly", "-json", db, sql)
	out, err := cmd.Output()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("sqlite3: %s", strings.TrimSpace(string(ee.Stderr)))
		}
		return nil, err
	}
	return out, nil
}

func decode[T any](b []byte) ([]T, error) {
	var v []T
	if len(strings.TrimSpace(string(b))) == 0 {
		return v, nil
	}
	return v, json.Unmarshal(b, &v)
}

const trackCols = `t.id, t.path, COALESCE(t.title,'') title, COALESCE(t.artist,'') artist, COALESCE(t.album,'') album,
  COALESCE(t.genre,'') genre, COALESCE(t.year,0) year, COALESCE(t.duration,0) duration, COALESCE(t.added_at,0) added_at`
const trackOrder = `ORDER BY t.album_artist COLLATE NOCASE, t.album COLLATE NOCASE, t.disc_no, t.track_no, t.title COLLATE NOCASE`

func sqlStr(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }

type smartRules struct {
	Genre    any    `json:"genre"`
	Artist   any    `json:"artist"`
	Album    any    `json:"album"`
	YearFrom any    `json:"yearFrom"`
	YearTo   any    `json:"yearTo"`
	Text     string `json:"text"`
	Query    string `json:"query"`
}

func list(v any) []string {
	switch x := v.(type) {
	case string:
		if x != "" {
			return []string{x}
		}
	case []any:
		var out []string
		for _, e := range x {
			if s, ok := e.(string); ok && s != "" {
				out = append(out, s)
			}
		}
		return out
	}
	return nil
}

// Same rules Muse's db.js rulesToWhere applies. A saved free-text "query" is approximated as a text match.
func rulesWhere(raw string) string {
	var r smartRules
	_ = json.Unmarshal([]byte(raw), &r)
	where := []string{"t.dup_of IS NULL"}
	in := func(col string, vals []string) {
		if len(vals) == 0 {
			return
		}
		q := make([]string, len(vals))
		for i, v := range vals {
			q[i] = sqlStr(v)
		}
		where = append(where, fmt.Sprintf("t.%s IN (%s)", col, strings.Join(q, ",")))
	}
	in("genre", list(r.Genre))
	in("artist", list(r.Artist))
	in("album", list(r.Album))
	if y := fmt.Sprint(r.YearFrom); r.YearFrom != nil && y != "" {
		where = append(where, "t.year >= "+sqlStr(y))
	}
	if y := fmt.Sprint(r.YearTo); r.YearTo != nil && y != "" {
		where = append(where, "t.year <= "+sqlStr(y))
	}
	for _, txt := range []string{r.Text, r.Query} {
		if txt != "" {
			l := sqlStr("%" + txt + "%")
			where = append(where, fmt.Sprintf("(t.title LIKE %s OR t.artist LIKE %s OR t.album LIKE %s)", l, l, l))
		}
	}
	return "WHERE " + strings.Join(where, " AND ")
}

func loadLibrary(db string) ([]Source, error) {
	if _, err := os.Stat(db); err != nil {
		return nil, fmt.Errorf("Muse library not found at %s (set MUSE_DB)", db)
	}
	b, err := query(db, "SELECT "+trackCols+" FROM tracks t WHERE t.dup_of IS NULL "+trackOrder)
	if err != nil {
		return nil, err
	}
	all, err := decode[Track](b)
	if err != nil {
		return nil, err
	}
	sources := []Source{{Name: "All Songs", Kind: "all", Orig: all}}

	type pl struct {
		ID    int64   `json:"id"`
		Name  string  `json:"name"`
		Rules *string `json:"rules"`
	}
	b, err = query(db, "SELECT id, name, rules FROM playlists ORDER BY name COLLATE NOCASE")
	if err == nil {
		pls, _ := decode[pl](b)
		for _, p := range pls {
			var sql, kind string
			if p.Rules != nil && *p.Rules != "" {
				kind = "smart"
				sql = "SELECT " + trackCols + " FROM tracks t " + rulesWhere(*p.Rules) + " " + trackOrder
			} else {
				kind = "playlist"
				sql = fmt.Sprintf("SELECT %s FROM playlist_tracks pt JOIN tracks t ON t.id = pt.track_id WHERE pt.playlist_id = %d ORDER BY pt.position", trackCols, p.ID)
			}
			if tb, err := query(db, sql); err == nil {
				if ts, err := decode[Track](tb); err == nil {
					sources = append(sources, Source{Name: p.Name, Kind: kind, Orig: ts})
				}
			}
		}
	}

	return sources, nil
}

var groupModes = []string{"Genres", "Artists", "Albums"}

// groupSources builds one auto playlist per genre / artist / album, like Muse's browse views.
func groupSources(all []Track, mode string) []Source {
	type grp struct {
		name   string
		tracks []Track
	}
	byKey := map[string]*grp{}
	var order []*grp
	for _, t := range all {
		var name string
		switch mode {
		case "Genres":
			name = strings.TrimSpace(strings.SplitN(t.Genre, ";", 2)[0])
		case "Artists":
			name = strings.TrimSpace(t.Artist)
		case "Albums":
			name = strings.TrimSpace(t.Album)
		}
		if name == "" || strings.HasPrefix(name, "<") || strings.HasPrefix(name, "Unknown") {
			continue
		}
		key := strings.ToLower(name) // "Juice Wrld" and "Juice WRLD" are one artist
		g := byKey[key]
		if g == nil {
			g = &grp{name: name}
			byKey[key] = g
			order = append(order, g)
		}
		g.tracks = append(g.tracks, t)
	}
	if mode == "Genres" {
		sort.SliceStable(order, func(i, j int) bool { return len(order[i].tracks) > len(order[j].tracks) })
	} else {
		sort.SliceStable(order, func(i, j int) bool { return strings.ToLower(order[i].name) < strings.ToLower(order[j].name) })
	}
	kind := strings.ToLower(strings.TrimSuffix(mode, "s"))
	out := make([]Source, len(order))
	for i, g := range order {
		out[i] = Source{Name: g.name, Kind: kind, Orig: g.tracks}
	}
	return out
}

var sortModes = []string{"Default", "Title", "Artist", "Album", "Year", "Length", "Added"}

func sortTracks(orig []Track, mode string) []Track {
	out := append([]Track(nil), orig...)
	lc := strings.ToLower
	title := func(t Track) string { return lc(t.titleOrFile()) }
	var less func(a, b Track) bool
	switch mode {
	case "Title":
		less = func(a, b Track) bool { return title(a) < title(b) }
	case "Artist":
		less = func(a, b Track) bool {
			if x, y := lc(a.Artist), lc(b.Artist); x != y {
				return x < y
			}
			return title(a) < title(b)
		}
	case "Album":
		less = func(a, b Track) bool { return lc(a.Album) < lc(b.Album) }
	case "Year":
		less = func(a, b Track) bool { return a.Year > b.Year }
	case "Length":
		less = func(a, b Track) bool { return a.Duration > b.Duration }
	case "Added":
		less = func(a, b Track) bool { return a.AddedAt > b.AddedAt }
	default:
		return out
	}
	sort.SliceStable(out, func(i, j int) bool { return less(out[i], out[j]) })
	return out
}
