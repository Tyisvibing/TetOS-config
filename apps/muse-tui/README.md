# muse-tui

Terminal player for the Muse library (cliamp-style layout, live FFT visualizer).

Reads `~/.config/muse-player/library.db` read-only (override with `--db` or `$MUSE_DB`).
Sources (Tab): All Songs, Muse playlists (manual + smart), then one auto playlist per genre, artist or album
(`m` switches the grouping). `S` sorts every list: Default, Title, Artist, Album, Year, Length, Added.
Playing a track snapshots that list as the queue, so regrouping/sorting never breaks playback (the queue follows the sort).
Grouping, sort, visualizer, volume, shuffle and repeat are remembered in `~/.config/muse-tui/state.json`.
Audio: ffmpeg decodes → oto plays via PulseAudio/PipeWire. Needs `ffmpeg` and `sqlite3` on PATH.

Build: `go build -o muse-tui . && install -m755 muse-tui ~/.local/bin/`

Keys: Space play/pause · Enter play · n/p next/prev · ←/→ seek 5s (H/L 30s) · +/- volume ·
s shuffle · r repeat (off/all/one) · v/V visualizer (Bars, Peaks, Mirror, Dots, Wave) ·
Tab/[ ] source · m/M grouping · S sort · / search · o jump to playing · x stop · q quit
