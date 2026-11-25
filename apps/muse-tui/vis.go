package main

import (
	"math"
	"math/cmplx"
	"strings"
)

const fftSize = 2048

var visModes = []string{"Bars", "Peaks", "Mirror", "Dots", "Wave"}

type Vis struct {
	mode    int
	samples []float32
	window  []float64
	bands   []float64 // smoothed 0..1
	peaks   []float64
	peakAge []int
}

func NewVis() *Vis {
	v := &Vis{samples: make([]float32, fftSize), window: make([]float64, fftSize)}
	for i := range v.window {
		v.window[i] = 0.5 - 0.5*math.Cos(2*math.Pi*float64(i)/float64(fftSize-1))
	}
	return v
}

func fft(a []complex128) {
	n := len(a)
	for i, j := 1, 0; i < n; i++ {
		bit := n >> 1
		for ; j&bit != 0; bit >>= 1 {
			j ^= bit
		}
		j ^= bit
		if i < j {
			a[i], a[j] = a[j], a[i]
		}
	}
	for size := 2; size <= n; size <<= 1 {
		w := cmplx.Rect(1, -2*math.Pi/float64(size))
		for start := 0; start < n; start += size {
			wk := complex(1, 0)
			for k := 0; k < size/2; k++ {
				u, t := a[start+k], wk*a[start+k+size/2]
				a[start+k], a[start+k+size/2] = u+t, u-t
				wk *= w
			}
		}
	}
}

// Update pulls fresh samples and recomputes n bands.
func (v *Vis) Update(e *Engine, n int) {
	if n < 1 {
		n = 1
	}
	if len(v.bands) != n {
		v.bands, v.peaks, v.peakAge = make([]float64, n), make([]float64, n), make([]int, n)
	}
	e.Samples(v.samples)
	buf := make([]complex128, fftSize)
	for i, s := range v.samples {
		buf[i] = complex(float64(s)*v.window[i], 0)
	}
	fft(buf)
	lo, hi := 40.0, 16000.0
	binHz := float64(sampleRate) / fftSize
	for b := 0; b < n; b++ {
		f0 := lo * math.Pow(hi/lo, float64(b)/float64(n))
		f1 := lo * math.Pow(hi/lo, float64(b+1)/float64(n))
		i0, i1 := int(f0/binHz), int(f1/binHz)
		if i1 <= i0 {
			i1 = i0 + 1
		}
		var m float64
		for i := i0; i < i1 && i < fftSize/2; i++ {
			if a := cmplx.Abs(buf[i]); a > m {
				m = a
			}
		}
		// tilt so highs aren't always tiny, then map dB to 0..1
		m *= 1 + float64(b)/float64(n)*2.5
		level := (20*math.Log10(m+1e-9) + 10) / 50
		level = math.Max(0, math.Min(1, level))
		if level > v.bands[b] {
			v.bands[b] = v.bands[b]*0.3 + level*0.7
		} else {
			v.bands[b] = math.Max(level, v.bands[b]-0.045)
		}
		if v.bands[b] >= v.peaks[b] {
			v.peaks[b], v.peakAge[b] = v.bands[b], 0
		} else if v.peakAge[b]++; v.peakAge[b] > 12 {
			v.peaks[b] = math.Max(0, v.peaks[b]-0.02)
		}
	}
}

func fg(c int) string { return "\x1b[38;5;" + itoa(c) + "m" }

const reset = "\x1b[0m"

func itoa(i int) string {
	if i < 10 {
		return string(rune('0' + i))
	}
	return itoa(i/10) + string(rune('0'+i%10))
}

// rowColor: green at the bottom, yellow in the middle, red at the top (terminal palette, so it follows the theme).
func rowColor(frac float64) int {
	switch {
	case frac > 0.82:
		return 9
	case frac > 0.55:
		return 11
	default:
		return 10
	}
}

var eighths = []rune(" ▁▂▃▄▅▆▇█")

// layout picks the band count and bar width for a given width.
func barLayout(width int) (n, bw int) {
	n = width / 5
	if n < 6 {
		n = 6
	}
	if n > 40 {
		n = 40
	}
	bw = (width - (n - 1)) / n
	if bw < 1 {
		bw = 1
	}
	return
}

func (v *Vis) Bands(width int) int {
	if visModes[v.mode] == "Wave" {
		return 1
	}
	n, _ := barLayout(width)
	return n
}

func (v *Vis) Render(width, height int) []string {
	if height < 1 {
		return nil
	}
	if visModes[v.mode] == "Wave" {
		return v.renderWave(width, height)
	}
	n, bw := barLayout(width)
	lines := make([]string, height)
	mode := visModes[v.mode]
	for row := 0; row < height; row++ {
		var sb strings.Builder
		var frac float64
		if mode == "Mirror" {
			mid := float64(height) / 2
			frac = math.Abs(float64(row)+0.5-mid) / mid
		} else {
			frac = float64(height-row) / float64(height)
		}
		col := rowColor(frac)
		sb.WriteString(fg(col))
		for b := 0; b < n && b < len(v.bands); b++ {
			if b > 0 {
				sb.WriteByte(' ')
			}
			sb.WriteString(v.cell(mode, b, row, height, bw, col))
		}
		sb.WriteString(reset)
		lines[row] = sb.String()
	}
	return lines
}

func (v *Vis) cell(mode string, b, row, height, bw, col int) string {
	level := v.bands[b]
	switch mode {
	case "Mirror":
		half := float64(height) / 2
		dist := math.Abs(float64(row) + 0.5 - half) // 0.5 .. half
		h := level * half
		ch := " "
		if dist-0.5 < h {
			ch = "█"
			if rem := h - (dist - 0.5); rem < 1 {
				ch = "▪"
			}
		}
		return strings.Repeat(ch, bw)
	case "Dots":
		h := level * float64(height)
		if float64(height-row) <= h+0.25 {
			return strings.Repeat("⣿", bw)
		}
		return strings.Repeat(" ", bw)
	}
	// Bars / Peaks: eighth-block precision
	h := level * float64(height) * 8
	base := float64((height - 1 - row) * 8)
	var ch rune
	switch {
	case h >= base+8:
		ch = '█'
	case h <= base:
		ch = ' '
	default:
		ch = eighths[int(h-base)]
	}
	if mode == "Peaks" && v.peaks[b] > 0.02 {
		prow := height - 1 - int(v.peaks[b]*float64(height)-0.001)
		if prow < 0 {
			prow = 0
		}
		if row == prow && ch != '█' {
			return fg(15) + strings.Repeat("▔", bw) + fg(col)
		}
	}
	return strings.Repeat(string(ch), bw)
}

// Oscilloscope drawn with braille dots (2x4 dots per cell).
func (v *Vis) renderWave(width, height int) []string {
	dw, dh := width*2, height*4
	grid := make([][]uint8, height)
	for i := range grid {
		grid[i] = make([]uint8, width)
	}
	bits := [4][2]uint8{{0x01, 0x08}, {0x02, 0x10}, {0x04, 0x20}, {0x40, 0x80}}
	set := func(x, y int) {
		if x < 0 || y < 0 || x >= dw || y >= dh {
			return
		}
		grid[y/4][x/2] |= bits[y%4][x%2]
	}
	// show the latest ~1024 samples, scaled with gentle auto-gain
	span := 1024
	src := v.samples[len(v.samples)-span:]
	var peak float32 = 0.05
	for _, s := range src {
		if s > peak {
			peak = s
		} else if -s > peak {
			peak = -s
		}
	}
	prev := -1
	for x := 0; x < dw; x++ {
		s := src[x*span/dw] / peak
		y := int((1 - float64(s)) / 2 * float64(dh-1))
		if prev >= 0 {
			a, b := prev, y
			if a > b {
				a, b = b, a
			}
			for yy := a; yy <= b; yy++ {
				set(x, yy)
			}
		} else {
			set(x, y)
		}
		prev = y
	}
	lines := make([]string, height)
	for r := 0; r < height; r++ {
		var sb strings.Builder
		sb.WriteString(fg(14))
		for c := 0; c < width; c++ {
			if grid[r][c] == 0 {
				sb.WriteByte(' ')
			} else {
				sb.WriteRune(rune(0x2800 + int(grid[r][c])))
			}
		}
		sb.WriteString(reset)
		lines[r] = sb.String()
	}
	return lines
}
