# Flash Markdown Viewer (AS1)

A tiny Markdown viewer written in **ActionScript 1** (Flash MX target, Player 6 era) that runs today via **Ruffle** (WebAssembly Flash emulator).  
It fetches a Markdown file over HTTP, parses a small subset, lays it out with dynamically created TextFields and shapes, supports images, and provides a custom draggable scrollbar.

> **Status:** Work in progress. Some documents won’t render perfectly yet and certain images may fail to load. See _Limitations_ below.

---

## Overview

- **What it is**: A SWF that downloads Markdown and renders it with a lightweight AS1 parser (headings, paragraphs, lists, quotes, fenced code, inline code, bold, horizontal rules, images).
- **How it runs**: Through **Ruffle** embedded in a simple `index.html`. No legacy plugins required.
- **Why**: To celebrate classic Flash tooling while exploring what’s still possible in 2025—especially for compact, distributable UI toys and viewers.

---

## Tech Stack

- **ActionScript 1 (Flash MX / Player 6)**  
  UI with TextFields and MovieClips, manual layout, custom scrollbar, HTTP via `LoadVars`, image loading via `loadMovie`.
- **Ruffle (web)**  
  WebAssembly Flash emulator; provides modern, safe playback in the browser.
- **HTML scaffold**  
  Minimal page that instantiates Ruffle and loads the SWF. (Optional: font injection for Japanese text).
- **Fonts (optional)**  
  `NotoSansJP-Regular.ttf` can be listed in `window.RufflePlayer.config.fontSources` to improve CJK rendering.
- **Hosting**  
  Any static server (local `python -m http.server`, GitHub Pages, etc.). Same‑origin is strongly recommended.

---

## ActionScript—very briefly

- **Networking**: `LoadVars.onData` receives the raw Markdown string.  
- **Rendering**: The viewer creates a vertical “panel” MovieClip and appends TextFields for each block (heading, paragraph, quote, code).  
- **Inline styles**: Minimal parsing for inline code `` `like this` `` and bold `**text**`.  
- **Images**: `![alt](url)` lines are detected and loaded via `loadMovie`. Images are fitted to the content width, with a max height.  
- **Scrolling**: A custom track + thumb. Dragging updates content `_y`; mousewheel is supported when the environment exposes it.  
- **Caveat**: AS1 has no native JSON or modern string utils; everything is manual and intentionally small.

---

## Getting Started

1. **Serve this folder** from a static HTTP server (examples):
   ```bash
   # Python 3
   python -m http.server 8000
   # or Node
   npx http-server . -p 8000
   ```
2. **Open** `http://localhost:8000/index.html` in a modern browser. Ruffle will load `flash_markdown_viewer.swf`.
3. **Type a Markdown URL** into the input field and press **Load**.  
   - Prefer **same-origin** files (e.g., `md/test.md`) or hosts that allow CORS.  
   - Raw gists and many static hosts are fine; some services (e.g., certain HackMD URLs) **block CORS**.
4. (Optional) **Enable fonts** by placing `NotoSansJP-Regular.ttf` next to `index.html` and configuring `window.RufflePlayer.config.fontSources` and `defaultFonts`.

---

## Configuration

- **Default URL**: Edit `DEFAULT_URL` in `main.as` (AS1) to choose what appears initially.
- **Heading rules**: H1/H2/H3 underline thickness and gaps can be tuned in `MD_STYLE` (e.g., `h1RuleThick`, `h2RuleGapTop`, etc.).
- **Image fit**: Images are downscaled to content width with a maximum height; upscaling is avoided to keep them sharp.
- **CORS**: For remote URLs, the server must send `Access-Control-Allow-Origin: *` (or your origin). Otherwise use same‑origin files.

---

## Limitations (WIP)

- **Markdown coverage** is intentionally small (no tables, HTML blocks, or complex inline nesting yet).
- **CORS** can block remote loads. Use same-origin assets or a host that permits cross‑origin fetches.
- **Images**: Very large images or slow hosts may time out; layout updates are triggered once sizes are known.
- **Layout quirks**: TextField metrics and fonts can differ across environments—expect spacing/line‑height differences.
- **Mouse wheel**: Only works when the browser/engine surfaces wheel events to Ruffle.
- **Performance**: Huge documents will be slower because layout is entirely script-driven.

---

## Roadmap

- Inline parsing improvements (links, emphasis nesting, strikethrough).
- Nested lists and better ordered‑list numbering.
- Smarter image loader (queueing, better error states, retry/backoff).
- Optional CORS proxy config (disabled by default).
- Export to static HTML/PNG snapshot (experimental).
- (Optional) AS2 port for Flash MX 2004 users—core stays AS1‑compatible.

---

## Acknowledgements

- **Macromedia / Adobe** for the Flash platform and the joy it brought to a generation of developers.  
- **Ruffle** contributors for keeping Flash content viewable in modern browsers.

---

## License

TBD. For now, treat this as **source available** for experimentation during development.
