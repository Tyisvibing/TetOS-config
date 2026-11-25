package main

import (
	"fmt"
	"math/rand"
	"os"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/ansi"
)

type tickMsg time.Time

func tick() tea.Cmd {
	return tea.Tick(33*time.Millisecond, func(t time.Time) tea.Msg { return tickMsg(t) })
}

var repeatNames = []string{"Off", "All", "One"}

type model struct {
	eng     *Engine
	vis     *Vis
	sources []Source
	src     int

	filter    string
	searching bool
	view      []int // indices into sources[src].Tracks after filtering
	cursor    int
	offset    int

	fixed    []Source // All Songs + Muse playlists
	all      []Track
	group    int // index into groupModes
	sortMode int // index into sortModes

	// What's playing is a snapshot of the source it was started from, so changing the grouping or sort
	// (or the source shown) never pulls the queue out from under the current song.
	queue     []Track
	queueOrig []Track
	queueName string
	playing   *Track
	playIdx   int
	history   []int
	shuffle   bool
	repeat    int
	fails     int
	stopped   bool
	flash     string
	flashTTL  int

	w, h int
}

func newModel(eng *Engine, fixed []Source) *model {
	m := &model{eng: eng, vis: NewVis(), fixed: fixed, all: fixed[0].Orig, stopped: true, w: 100, h: 32}
	st := loadState()
	m.group = st.Group % len(groupModes)
	m.sortMode = st.Sort % len(sortModes)
	m.vis.mode = st.Vis % len(visModes)
	m.shuffle, m.repeat = st.Shuffle, st.Repeat%3
	if st.Volume > 0 {
		eng.SetVolume(st.Volume)
	}
	m.rebuild()
	return m
}

func (m *model) saveState() {
	saveState(state{Group: m.group, Sort: m.sortMode, Vis: m.vis.mode, Volume: m.eng.Volume(), Shuffle: m.shuffle, Repeat: m.repeat})
}

// rebuild regroups the source list for the current group mode and applies the sort everywhere.
func (m *model) rebuild() {
	cur := ""
	if m.src < len(m.sources) {
		cur = m.sources[m.src].Kind + "\x00" + m.sources[m.src].Name
	}
	m.sources = append(append([]Source(nil), m.fixed...), groupSources(m.all, groupModes[m.group])...)
	m.src = 0
	for i, s := range m.sources {
		if s.Kind+"\x00"+s.Name == cur {
			m.src = i
		}
	}
	m.resort()
}

func (m *model) resort() {
	mode := sortModes[m.sortMode]
	for i := range m.sources {
		m.sources[i].Tracks = sortTracks(m.sources[i].Orig, mode)
	}
	if m.queueOrig != nil {
		m.queue = sortTracks(m.queueOrig, mode)
		m.history = nil
		if m.playing != nil {
			for i, t := range m.queue {
				if t.ID == m.playing.ID {
					m.playIdx = i
				}
			}
		}
	}
	m.refilter()
}

// startQueue snapshots source si and plays its track idx.
func (m *model) startQueue(si, idx int) {
	m.queueOrig = m.sources[si].Orig
	m.queue = m.sources[si].Tracks
	m.queueName = m.sources[si].Name
	m.fails, m.history = 0, nil
	m.playQ(idx, 0)
}

func (m *model) Init() tea.Cmd { return tick() }

func (m *model) tracks() []Track { return m.sources[m.src].Tracks }

func (m *model) refilter() {
	m.view = m.view[:0]
	q := strings.ToLower(m.filter)
	for i, t := range m.tracks() {
		if q == "" || strings.Contains(strings.ToLower(t.Display()+" "+t.Album+" "+t.Genre), q) {
			m.view = append(m.view, i)
		}
	}
	if m.cursor >= len(m.view) {
		m.cursor = max(0, len(m.view)-1)
	}
}

func (m *model) say(s string) { m.flash, m.flashTTL = s, 90 }

func (m *model) playQ(idx int, offset float64) {
	list := m.queue
	if idx < 0 || idx >= len(list) {
		return
	}
	t := list[idx]
	if _, err := os.Stat(t.Path); err != nil {
		m.fails++
		m.say("missing file: " + t.Display())
		if m.fails >= len(list) {
			m.stop()
			m.say("no playable tracks in " + m.queueName)
			return
		}
		m.playIdx = idx
		m.next(false)
		return
	}
	if err := m.eng.Play(t.Path, offset); err != nil {
		m.say("ffmpeg: " + err.Error())
		return
	}
	cp := t
	m.playing, m.playIdx, m.stopped = &cp, idx, false
}

func (m *model) stop() {
	m.eng.Stop()
	m.stopped = true
}

func (m *model) next(user bool) {
	list := m.queue
	if len(list) == 0 {
		return
	}
	if !user && m.repeat == 2 {
		m.playQ(m.playIdx, 0)
		return
	}
	m.history = append(m.history, m.playIdx)
	if m.shuffle && len(list) > 1 {
		n := rand.Intn(len(list) - 1)
		if n >= m.playIdx {
			n++
		}
		m.playQ(n, 0)
		return
	}
	n := m.playIdx + 1
	if n >= len(list) {
		if m.repeat == 0 && !user {
			m.stop()
			return
		}
		n = 0
	}
	m.playQ(n, 0)
}

func (m *model) prev() {
	if m.playing == nil {
		return
	}
	if m.eng.Position() > 3 {
		m.playQ(m.playIdx, 0)
		return
	}
	if l := len(m.history); l > 0 {
		i := m.history[l-1]
		m.history = m.history[:l-1]
		m.playQ(i, 0)
		return
	}
	m.playQ(max(0, m.playIdx-1), 0)
}

func (m *model) seek(d float64) {
	if m.playing == nil || m.stopped {
		return
	}
	pos := m.eng.Position() + d
	if pos < 0 {
		pos = 0
	}
	if m.playing.Duration > 0 && pos > m.playing.Duration-1 {
		pos = m.playing.Duration - 1
	}
	paused := m.eng.Paused()
	m.playQ(m.playIdx, pos)
	if paused {
		m.eng.TogglePause()
	}
}

func (m *model) listHeight() int { _, lh := m.heights(); return lh }

func (m *model) heights() (visH, listH int) {
	visH = (m.h - 8) / 3
	visH = max(3, min(10, visH))
	listH = m.h - 7 - visH
	return visH, max(1, listH)
}

func (m *model) moveCursor(d int) {
	m.cursor = max(0, min(len(m.view)-1, m.cursor+d))
}

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
	case tickMsg:
		if !m.stopped && m.eng.Done() {
			m.fails = 0
			m.next(false)
		}
		m.vis.Update(m.eng, m.vis.Bands(m.w-6))
		if m.flashTTL > 0 {
			if m.flashTTL--; m.flashTTL == 0 {
				m.flash = ""
			}
		}
		return m, tick()
	case tea.MouseMsg:
		switch msg.Button {
		case tea.MouseButtonWheelUp:
			m.moveCursor(-3)
		case tea.MouseButtonWheelDown:
			m.moveCursor(3)
		}
	case tea.KeyMsg:
		if m.searching {
			switch msg.Type {
			case tea.KeyEsc:
				m.searching, m.filter = false, ""
				m.refilter()
			case tea.KeyEnter:
				m.searching = false
			case tea.KeyBackspace:
				if r := []rune(m.filter); len(r) > 0 {
					m.filter = string(r[:len(r)-1])
					m.refilter()
				}
			case tea.KeyRunes, tea.KeySpace:
				m.filter += string(msg.Runes)
				if msg.Type == tea.KeySpace {
					m.filter += " "
				}
				m.cursor = 0
				m.refilter()
			case tea.KeyUp, tea.KeyDown:
				m.moveCursor(map[bool]int{true: -1, false: 1}[msg.Type == tea.KeyUp])
			}
			return m, nil
		}
		switch msg.String() {
		case "q", "ctrl+c":
			m.eng.Stop()
			m.saveState()
			return m, tea.Quit
		case "j", "down":
			m.moveCursor(1)
		case "k", "up":
			m.moveCursor(-1)
		case "pgdown", "ctrl+d":
			m.moveCursor(m.listHeight())
		case "pgup", "ctrl+u":
			m.moveCursor(-m.listHeight())
		case "g", "home":
			m.cursor = 0
		case "G", "end":
			m.cursor = len(m.view) - 1
		case "enter":
			if len(m.view) > 0 {
				m.startQueue(m.src, m.view[m.cursor])
			}
		case " ":
			if m.stopped {
				if len(m.view) > 0 {
					m.startQueue(m.src, m.view[m.cursor])
				}
			} else {
				m.eng.TogglePause()
			}
		case "n", ">", ".":
			if m.playing != nil {
				m.next(true)
			}
		case "p", "<", ",":
			m.prev()
		case "right", "l":
			m.seek(5)
		case "left", "h":
			m.seek(-5)
		case "L", "shift+right":
			m.seek(30)
		case "H", "shift+left":
			m.seek(-30)
		case "+", "=":
			m.eng.SetVolume(m.eng.Volume() + 0.05)
		case "-", "_":
			m.eng.SetVolume(m.eng.Volume() - 0.05)
		case "s":
			m.shuffle = !m.shuffle
		case "r":
			m.repeat = (m.repeat + 1) % 3
		case "v":
			m.vis.mode = (m.vis.mode + 1) % len(visModes)
		case "V":
			m.vis.mode = (m.vis.mode + len(visModes) - 1) % len(visModes)
		case "x":
			m.stop()
		case "tab", "]":
			m.switchSource(1)
		case "shift+tab", "[":
			m.switchSource(-1)
		case "/":
			m.searching = true
		case "esc":
			if m.filter != "" {
				m.filter = ""
				m.refilter()
			}
		case "o":
			m.jumpToPlaying()
		case "m":
			m.group = (m.group + 1) % len(groupModes)
			m.regroup()
		case "M":
			m.group = (m.group + len(groupModes) - 1) % len(groupModes)
			m.regroup()
		case "S":
			m.sortMode = (m.sortMode + 1) % len(sortModes)
			m.resort()
			m.say("sorted by " + sortLabel(m.sortMode))
		}
	}
	return m, nil
}

func sortLabel(i int) string {
	switch sortModes[i] {
	case "Default":
		return "default order"
	case "Year":
		return "year (newest first)"
	case "Length":
		return "length (longest first)"
	case "Added":
		return "recently added"
	}
	return strings.ToLower(sortModes[i])
}

// regroup applies a new group mode and shows its first group (Tab steps through the rest).
func (m *model) regroup() {
	m.rebuild()
	if len(m.sources) > len(m.fixed) {
		m.src, m.cursor, m.offset, m.filter = len(m.fixed), 0, 0, ""
		m.refilter()
	}
	m.say(fmt.Sprintf("grouping by %s (%d) — Tab to step through them", groupModes[m.group], len(m.sources)-len(m.fixed)))
}

// jumpToPlaying moves the cursor to the playing track, switching to All Songs if it isn't in this list.
func (m *model) jumpToPlaying() {
	if m.playing == nil {
		return
	}
	find := func() bool {
		for i, v := range m.view {
			if m.tracks()[v].ID == m.playing.ID {
				m.cursor = i
				return true
			}
		}
		return false
	}
	if find() {
		return
	}
	m.filter = ""
	m.refilter()
	if find() {
		return
	}
	for i, s := range m.sources {
		if s.Name == m.queueName {
			m.src = i
			break
		}
	}
	m.refilter()
	if !find() {
		m.src = 0
		m.refilter()
		find()
	}
}

func (m *model) switchSource(d int) {
	m.src = (m.src + d + len(m.sources)) % len(m.sources)
	m.cursor, m.offset, m.filter = 0, 0, ""
	m.refilter()
}

// ---------- view ----------

var (
	cTitle  = "\x1b[1m" + fg(10)
	cTrack  = fg(11)
	cText   = fg(15)
	cDim    = fg(7)
	cGreen  = fg(2)
	cAccent = fg(11)
	cBold   = "\x1b[1m"
)

func fmtTime(s float64) string {
	if s < 0 {
		s = 0
	}
	t := int(s)
	return fmt.Sprintf("%02d:%02d", t/60, t%60)
}

// spread puts left and right on one line of width w.
func spread(left, right string, w int) string {
	gap := w - ansi.StringWidth(left) - ansi.StringWidth(right)
	if gap < 1 {
		left = ansi.Truncate(left, max(0, w-ansi.StringWidth(right)-1), "…")
		gap = max(1, w-ansi.StringWidth(left)-ansi.StringWidth(right))
	}
	return left + reset + strings.Repeat(" ", gap) + right + reset
}

// rule clips a line that ends in a ─ rule to w without an ellipsis.
func rule(s string, w int) string { return ansi.Truncate(s, w, "") + reset }

func fit(s string, w int) string {
	s = ansi.Truncate(s, w, "…")
	if pad := w - ansi.StringWidth(s); pad > 0 {
		s += reset + strings.Repeat(" ", pad)
	}
	return s + reset
}

func (m *model) View() string {
	W := max(20, m.w-6)
	visH, listH := m.heights()
	var out []string
	add := func(s string) { out = append(out, "   "+s+reset) }

	// header
	src := m.sources[m.src]
	add(spread(cTitle+"M U S E", cDim+"["+src.Name+"]", W))
	nowTitle := cDim + "♫ —"
	if m.playing != nil && !m.stopped {
		nowTitle = cTrack + "♫ " + m.playing.Display()
	}
	add(fit(nowTitle, W))
	pos, dur := 0.0, 0.0
	if m.playing != nil && !m.stopped {
		pos, dur = m.eng.Position(), m.playing.Duration
	}
	state := cDim + "■ Stopped"
	switch {
	case m.stopped:
	case m.eng.Paused():
		state = cAccent + "❚❚ Paused"
	default:
		state = cGreen + "▶ Playing"
	}
	add(spread(cText+fmtTime(pos)+" / "+fmtTime(dur), state, W))
	add("")

	// visualiser
	for _, l := range m.vis.Render(W, visH) {
		add(l)
	}

	// seek bar
	frac := 0.0
	if dur > 0 {
		frac = min(1, pos/dur)
	}
	filled := int(frac * float64(W-1))
	add(cAccent + strings.Repeat("━", filled) + "●" + cDim + strings.Repeat("─", W-1-filled))

	// panels
	rightW := 30
	leftW := W - rightW - 5
	if leftW < 20 {
		rightW, leftW = 0, W
	}
	listHead := cBold + cAccent + "▸─ " + src.Name + " ── " + reset + cDim + fmt.Sprintf("[%d/%d] ", min(m.cursor+1, len(m.view)), len(m.view))
	if m.searching || m.filter != "" {
		cur := ""
		if m.searching {
			cur = "█"
		}
		listHead += cAccent + "/" + m.filter + cur + " " + cDim
	}
	listHead = rule(listHead+strings.Repeat("─", W), leftW)

	if m.cursor < m.offset {
		m.offset = m.cursor
	}
	if m.cursor >= m.offset+listH {
		m.offset = m.cursor - listH + 1
	}
	left := []string{listHead}
	tracks := m.tracks()
	for r := 0; r < listH; r++ {
		i := m.offset + r
		if i >= len(m.view) {
			left = append(left, strings.Repeat(" ", leftW))
			continue
		}
		t := tracks[m.view[i]]
		mark, play := " ", " "
		if i == m.cursor {
			mark = cDim + ">"
		}
		isPlaying := m.playing != nil && !m.stopped && t.ID == m.playing.ID
		name := cText + fmt.Sprintf("%3d. ", m.view[i]+1) + t.Display()
		if isPlaying {
			play = cBold + cTitle + "▶" + reset
			name = cBold + cTrack + fmt.Sprintf("%3d. ", m.view[i]+1) + t.Display() + reset
		} else if i == m.cursor {
			name = cBold + name + reset
		}
		if t.Album != "" && !strings.HasPrefix(t.Album, "Unknown") {
			name += cDim + " · " + t.Album
		}
		left = append(left, fit(mark+play+"  "+name, leftW))
	}

	right := m.settingsPanel(rightW)
	for i := 0; i < len(left); i++ {
		line := left[i]
		if rightW > 0 {
			r := ""
			if i < len(right) {
				r = right[i]
			}
			if strings.Contains(r, "──") {
				line += "     " + rule(r, rightW)
			} else {
				line += "     " + fit(r, rightW)
			}
		}
		add(line)
	}

	// help bar / flash
	if m.flash != "" {
		add(fit(fg(9)+"! "+m.flash, W))
	} else {
		add(fit(m.helpBar(), W))
	}
	return strings.Join(out, "\n")
}

func chip(k, label string) string {
	return "\x1b[1m" + fg(15) + "\x1b[48;5;8m " + k + " " + reset + cDim + " " + label + " "
}

func (m *model) helpBar() string {
	if m.searching {
		return chip("Enter", "Keep filter") + chip("Esc", "Clear") + chip("↑↓", "Move")
	}
	return chip("Space", "Play/Pause") + chip("n/p", "Next/Prev") + chip("←→", "Seek") +
		chip("Tab", "Source") + chip("m", "Group") + chip("S", "Sort") + chip("/", "Search") + chip("v", "Visualizer") + chip("s/r", "Shuffle/Repeat") +
		chip("+/-", "Vol") + chip("o", "Go to playing") + chip("q", "Quit")
}

func (m *model) settingsPanel(w int) []string {
	if w == 0 {
		return nil
	}
	lbl := func(k string) string { return "\x1b[1m" + fg(15) + k + " " + reset }
	br := func(v string) string { return cDim + "[" + cAccent + v + cDim + "]" }
	onoff := map[bool]string{true: "On", false: "Off"}
	vol := m.eng.Volume()
	n := int(vol*20 + 0.5)
	lines := []string{
		cDim + strings.Repeat("─", 2) + " Settings " + strings.Repeat("─", w),
		lbl("SRC") + br(m.sources[m.src].Name) + cDim + fmt.Sprintf(" %d/%d", m.src+1, len(m.sources)),
		lbl("VOL") + cGreen + strings.Repeat("█", n) + cDim + strings.Repeat("░", 20-n) + fmt.Sprintf(" %d%%", int(vol*100+0.5)),
		lbl("GRP") + br(groupModes[m.group]) + cDim + " m",
		lbl("SRT") + br(sortModes[m.sortMode]) + cDim + " S",
		lbl("SHF") + br(onoff[m.shuffle]),
		lbl("RPT") + br(repeatNames[m.repeat]),
		lbl("VIS") + br(visModes[m.vis.mode]),
		"",
	}
	if t := m.playing; t != nil && !m.stopped {
		lines = append(lines, cDim+"── Now Playing "+strings.Repeat("─", w))
		if t.Artist != "" {
			lines = append(lines, lbl("ART")+cText+t.Artist)
		}
		if t.Album != "" {
			lines = append(lines, lbl("ALB")+cText+t.Album)
		}
		if t.Genre != "" {
			lines = append(lines, lbl("GEN")+cText+t.Genre)
		}
		if t.Year > 0 {
			lines = append(lines, lbl("YR ")+cText+fmt.Sprint(t.Year))
		}
		lines = append(lines, lbl("QUE")+cText+m.queueName)
	}
	return lines
}

func main() {
	db := defaultDB()
	for i := 1; i < len(os.Args); i++ {
		switch os.Args[i] {
		case "--db":
			if i+1 < len(os.Args) {
				db = os.Args[i+1]
				i++
			}
		case "-h", "--help":
			fmt.Println("muse-tui — terminal player for your Muse library\n\nusage: muse-tui [--db path/to/library.db]\n(default: ~/.config/muse-player/library.db, or $MUSE_DB)")
			return
		}
	}
	sources, err := loadLibrary(db)
	if err != nil {
		fmt.Fprintln(os.Stderr, "muse-tui:", err)
		os.Exit(1)
	}
	if len(sources[0].Orig) == 0 {
		fmt.Fprintln(os.Stderr, "muse-tui: the Muse library is empty — add a folder in Muse first")
		os.Exit(1)
	}
	eng, err := NewEngine()
	if err != nil {
		fmt.Fprintln(os.Stderr, "muse-tui: audio:", err)
		os.Exit(1)
	}
	p := tea.NewProgram(newModel(eng, sources), tea.WithAltScreen(), tea.WithMouseCellMotion())
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, "muse-tui:", err)
		os.Exit(1)
	}
}
