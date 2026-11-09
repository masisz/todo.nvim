# Real-machine checks for the roadmap viewer

Automated checks that already pass on Linux/Chromium:

```bash
nvim -l tests/run.lua
```

```bash
node tests/e2e/viewer_check.js
```

The items below need Windows and macOS. Record the result (OK / NG + note) next to each.

## 1. Atomic writes (Windows, macOS)

`uv.fs_rename` must replace an existing `deps.txt` / export file, also while another program has
it open for reading.

```bash
nvim -l tests/run.lua tests/fsutil_spec.lua
```

- [ ] Windows: all 3 tests pass
- [ ] macOS: all 3 tests pass

## 2. Opening the viewer URL (Windows, macOS)

The URL carries the token in its fragment (`http://127.0.0.1:<port>/#token=...`).
On Windows it is opened with `rundll32 url.dll,FileProtocolHandler`; that path must keep the
fragment.

- [ ] Windows: `:RoadmapView` opens the default browser and the page loads data (no "Missing token" status)
- [ ] macOS: same with Safari as the default browser
- [ ] macOS: same with Chrome as the default browser

## 3. Safari (macOS)

First, WebKit through Playwright (needs `npx playwright install webkit`):

```bash
BROWSER=webkit node tests/e2e/viewer_check.js
```

- [ ] WebKit: all checks pass

Then real Safari, on a roadmap with Japanese titles, via `:RoadmapView`:

- [ ] Graph and gantt render; Japanese text uses Hiragino (not a fallback box font)
- [ ] Export → Both PNG / Graph PNG / Gantt PNG: files appear in `roadmap/export/`, open in Preview,
      text is rendered (SVG -> canvas works without tainting; Japanese glyphs present)
- [ ] Export → SVG: files open in Safari and Preview
- [ ] Export → Mermaid: `roadmap/export/roadmap.md` renders in GitHub / VS Code preview
- [ ] Keys: arrows, h/j/k/l, `/` search, `1`/`2`/`3`, `+`/`-`/`0`, `e`, `m`, `R`, `?`, `Esc`
- [ ] Clicking a dependency line selects it (orange); Delete / Backspace removes it from `deps.txt`
- [ ] ⌘ + wheel / pinch zooms the diagram, not the page
- [ ] Editing a milestone file in Neovim updates the page within ~2 s
- [ ] After `:RoadmapViewStop`, the red "Cannot reach Neovim" banner appears

## 4. Edge on Windows

- [ ] Same list as Safari above (fonts: Yu Gothic UI / Meiryo)
- [ ] Files written with CRLF line endings by Windows editors are read correctly
