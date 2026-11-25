package main

// Playback: ffmpeg decodes any format to 16-bit stereo PCM, oto plays it. Every decoded frame is also copied
// into a ring buffer keyed by absolute frame number, so the visualiser can look at exactly the frames that
// are coming out of the speakers right now (frames read minus what is still sitting in oto's buffer).

import (
	"encoding/binary"
	"io"
	"os/exec"
	"strconv"
	"sync"
	"time"

	"github.com/ebitengine/oto/v3"
)

const (
	sampleRate = 44100
	channels   = 2
	frameBytes = 4
	ringSize   = 1 << 16 // frames
)

type Engine struct {
	ctx *oto.Context

	mu     sync.Mutex
	cur    *stream
	volume float64
	paused bool
}

type stream struct {
	cmd    *exec.Cmd
	out    io.ReadCloser
	player *oto.Player
	start  float64 // seconds offset the decode started at

	mu       sync.Mutex
	read     int64 // bytes handed to oto
	eof      bool
	partial  []byte
	ring     [ringSize]float32
	ringHead int64 // absolute frame count written
}

func NewEngine() (*Engine, error) {
	ctx, ready, err := oto.NewContext(&oto.NewContextOptions{
		SampleRate:   sampleRate,
		ChannelCount: channels,
		Format:       oto.FormatSignedInt16LE,
		BufferSize:   60 * time.Millisecond,
	})
	if err != nil {
		return nil, err
	}
	<-ready
	return &Engine{ctx: ctx, volume: 0.8}, nil
}

func (s *stream) Read(p []byte) (int, error) {
	n, err := s.out.Read(p)
	if n > 0 {
		s.mu.Lock()
		buf := append(s.partial, p[:n]...)
		whole := len(buf) / frameBytes * frameBytes
		for i := 0; i < whole; i += frameBytes {
			l := int16(binary.LittleEndian.Uint16(buf[i:]))
			r := int16(binary.LittleEndian.Uint16(buf[i+2:]))
			s.ring[s.ringHead&(ringSize-1)] = (float32(l) + float32(r)) / 65536
			s.ringHead++
		}
		s.partial = append(s.partial[:0], buf[whole:]...)
		s.read += int64(n)
		s.mu.Unlock()
	}
	if err != nil {
		s.mu.Lock()
		s.eof = true
		s.mu.Unlock()
		if err != io.EOF {
			err = io.EOF
		}
	}
	return n, err
}

// Play starts path at offset seconds, replacing whatever was playing.
func (e *Engine) Play(path string, offset float64) error {
	e.Stop()
	args := []string{"-nostdin", "-loglevel", "quiet"}
	if offset > 0 {
		args = append(args, "-ss", strconv.FormatFloat(offset, 'f', 3, 64))
	}
	args = append(args, "-i", path, "-vn", "-f", "s16le", "-ac", "2", "-ar", strconv.Itoa(sampleRate), "-")
	cmd := exec.Command("ffmpeg", args...)
	out, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	s := &stream{cmd: cmd, out: out, start: offset}
	s.player = e.ctx.NewPlayer(s)
	e.mu.Lock()
	s.player.SetVolume(e.volume)
	e.cur = s
	e.paused = false
	e.mu.Unlock()
	s.player.Play()
	return nil
}

func (e *Engine) Stop() {
	e.mu.Lock()
	s := e.cur
	e.cur = nil
	e.paused = false
	e.mu.Unlock()
	if s == nil {
		return
	}
	s.player.Pause()
	if s.cmd.Process != nil {
		_ = s.cmd.Process.Kill()
	}
	go func() { _ = s.cmd.Wait(); _ = s.player.Close() }()
}

func (e *Engine) TogglePause() {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.cur == nil {
		return
	}
	e.paused = !e.paused
	if e.paused {
		e.cur.player.Pause()
	} else {
		e.cur.player.Play()
	}
}

func (e *Engine) Paused() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.cur != nil && e.paused
}

func (e *Engine) Active() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.cur != nil
}

func (s *stream) finished() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.eof
}

// Done reports that the current track has fully played out.
func (e *Engine) Done() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.cur != nil && !e.paused && e.cur.finished() && !e.cur.player.IsPlaying()
}

func (e *Engine) SetVolume(v float64) {
	if v < 0 {
		v = 0
	}
	if v > 1 {
		v = 1
	}
	e.mu.Lock()
	e.volume = v
	if e.cur != nil {
		e.cur.player.SetVolume(v)
	}
	e.mu.Unlock()
}

func (e *Engine) Volume() float64 { e.mu.Lock(); defer e.mu.Unlock(); return e.volume }

// playedFrame is the absolute frame index currently audible.
func (s *stream) playedFrame() int64 {
	buffered := int64(s.player.BufferedSize())
	s.mu.Lock()
	defer s.mu.Unlock()
	f := (s.read - buffered) / frameBytes
	if f < 0 {
		f = 0
	}
	return f
}

func (e *Engine) Position() float64 {
	e.mu.Lock()
	s := e.cur
	e.mu.Unlock()
	if s == nil {
		return 0
	}
	return s.start + float64(s.playedFrame())/sampleRate
}

// Samples fills dst with the most recent audible mono samples (zeros when paused or stopped).
func (e *Engine) Samples(dst []float32) {
	e.mu.Lock()
	s := e.cur
	e.mu.Unlock()
	for i := range dst {
		dst[i] = 0
	}
	if s == nil || !s.player.IsPlaying() {
		return
	}
	end := s.playedFrame()
	s.mu.Lock()
	defer s.mu.Unlock()
	if end > s.ringHead {
		end = s.ringHead
	}
	n := int64(len(dst))
	for i := int64(0); i < n; i++ {
		f := end - n + i
		if f < 0 || f < s.ringHead-ringSize {
			continue
		}
		dst[i] = s.ring[f&(ringSize-1)]
	}
}
