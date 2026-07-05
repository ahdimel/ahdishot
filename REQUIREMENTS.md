# ahdishot — Requirements & Scoping

> A lightweight, **native Apple Silicon** screenshot + annotation app for macOS, built to replace
> Lightshot v2.22 (Intel-only, requires Rosetta) ahead of Apple's removal of Rosetta support.
>
> **Status:** Requirements draft — v0.1 (2026-07-05). Decisions below are confirmed with the owner
> unless marked _TBD_. This document is the single source of truth for handoff to sub-agents.

---

## 1. Motivation & goals

- The owner relies on **Lightshot Screenshot v2.22** (`x86_64`-only Mach-O, built 2019, distributed via
  the Mac App Store). It runs today only through **Rosetta 2**, which Apple is winding down.
- **Goal:** a from-scratch, native `arm64` app — **ahdishot** — that reproduces the slice of Lightshot
  the owner actually uses. This is **not** a port/decompile of Lightshot (no source exists); it is a
  clean-room reimplementation of equivalent user-facing behavior.
- Secondary goal: keep the door open to a future **Mac App Store** release (free or small one-time fee).

### Non-negotiable constraints
1. **Native `arm64`** — no Rosetta, no bundled cross-platform runtime (no Electron/Qt).
2. **Extremely lightweight** — see the resource budget in §6.
3. Reproduce the **look & feel of Lightshot's inline annotation editor** (owner liked it).

---

## 2. Confirmed decisions (from scoping Q&A)

| Area | Decision |
|---|---|
| App name | **ahdishot** |
| Capture scope | **Region-only** — drag-select a rectangle; no full-screen quick-capture shortcut |
| Capture flow | **Inline editor**, Lightshot-style — toolbar attaches to the selection; annotate in place, then act |
| Editor actions | **Copy**, **Save**, **Close** — **no Print** (user saves, then prints via the OS) |
| Annotation tool set | **Full Lightshot set**: rectangle, ellipse, arrow, line, pencil (freehand), marker/highlighter, text, color, undo |
| Color chooser | **Fixed palette** of preset swatches (no full macOS color picker in v1) |
| Menu bar | **Yes** — menu bar icon for capture, Settings, Quit |
| Save behavior | **Auto-save** silently to a folder (no dialog); timestamped filename |
| Save + clipboard | **Separate actions** — Save writes to disk only; Copy is a distinct button (no auto-copy on save) |
| Image format | **Configurable, default PNG** (PNG or JPG) |
| Post-save feedback | **Silent** — no sound, notification, or thumbnail |
| Global hotkey | **⌘ + 1** (owner's explicit choice; user-configurable). ⚠️ Shadows ⌘1 in all apps while running |
| Launch at login | **Yes** — user-toggleable |
| Minimum macOS | **macOS 15 (Sequoia)** and later |
| Source licensing | **Proprietary / closed** (App-Store-compatible; owner retains all rights) |

---

## 3. Functional requirements

### 3.1 Activation & capture
- **FR-1** The app runs as a background agent and is triggered by a **global hotkey (default ⌘1)** from
  any app or state, including while a video plays full-screen or a game is running. The capture is a
  still snapshot of the screen at the instant the hotkey is pressed.
- **FR-2** On trigger, the app enters **region-selection mode**: a dim overlay covers **all connected
  displays**; the user **drag-selects** a rectangular region. Live pixel **dimensions** are shown.
- **FR-3** The selection can be **adjusted by its edge/corner handles** before committing.
- **FR-4** **Esc** (or right-click) cancels capture with no side effects. Clicking outside / pressing
  Enter commits.
- **FR-5** Capture is at **native (Retina) pixel resolution**; multi-display and mixed-DPI setups
  produce correctly-scaled output.
- **FR-6** _Out of scope (v1, owner decision):_ no dedicated full-screen quick-capture shortcut. To
  capture the whole screen, the user manually drag-selects the full region.

### 3.2 Inline annotation editor (Lightshot-style)
- **FR-7** After the region is committed, a **toolbar attaches to the selection** (see §4 for layout),
  and the region becomes an editable canvas. Annotations are drawn **on top of** the captured image
  and flattened on export.
- **FR-8** Tools (full set):
  - **Rectangle** (outline)
  - **Ellipse / circle** (outline)
  - **Arrow** (pointing arrow)
  - **Line** (straight)
  - **Pencil** (freehand)
  - **Marker / highlighter** (translucent stroke)
  - **Text** box — editable text with adjustable **size** and **color**
  - **Color** — selects the active color from the **fixed palette** for subsequent shapes/text
  - **Undo** — reverts the last annotation (support a reasonable multi-step history)
- **FR-9** Shapes support **varying thickness** (a small set of stroke widths and/or a stepper). Text
  supports **varying size**. All shapes and text use the **active palette color**.
- **FR-10** Annotations are **non-destructive during editing** (each is an object that can be undone);
  they are rasterized only on Copy/Save/Print.

### 3.3 Actions (from the editor)
- **FR-11** **Save** — silently write the flattened image to the configured folder using the configured
  format, with a **timestamped filename** (e.g. `ahdishot_2026-07-05_at_14.32.08.png`). No dialog, no
  auto-copy, no feedback (per decisions).
- **FR-12** **Copy** — put the flattened image on the clipboard (distinct button; does not save).
- **FR-13** **Close / Cancel** — dismiss the editor without saving.

  _Print is intentionally out of scope (owner decision):_ to print, the user saves the image and uses the
  standard system print workflow. ahdishot does not talk to printers.

### 3.4 Menu bar & settings
- **FR-15** A **menu bar icon** exposes: _Capture now_, _Settings…_, _Launch at login_ (toggle), _Quit_.
- **FR-16** **Settings** window lets the user configure:
  - Global **hotkey** (default ⌘1)
  - Default **save folder** (default `~/Pictures/ahdishot/`)
  - **Image format** (PNG default / JPG)
  - **Launch at login** on/off
  - Default annotation **color** and **thickness** (optional)
- **FR-17** **Launch at login** is user-toggleable and persists across reboots (via `SMAppService`).

### 3.5 Persistence
- **FR-18** Settings persist across launches (`UserDefaults`, or app-group defaults if sandboxed).
- **FR-19** Default save folder is created on first use if missing.

---

## 4. Annotation UI spec (Lightshot-inspired) — CONFIRMED

Layout and behavior (confirmed with owner):

- **Dimmed backdrop:** after the region is committed, everything outside the selection is dimmed; the
  selection shows the crisp captured pixels.
- **Single combined toolbar:** one **horizontal bar** sits just **outside the bottom edge** of the
  selection and holds **both draw tools and actions**, left-to-right:
  - _Draw tools:_ rectangle, ellipse, arrow, line, pencil (freehand), marker/highlighter, text, undo.
  - _Separator._
  - _Actions:_ copy, save, close.
  - Color is chosen **inside each tool's options popover** (below), not as a standalone toolbar button.
- **Tool options popover:** selecting a draw tool opens a small **popover** anchored to that tool button,
  showing the **fixed color palette** swatches and **thickness** options — and, for the **text** tool, the
  **pre-selected text size** from the wide preset range in §5. Each tool remembers its last-used settings.
  This mirrors the classic Lightshot feel.
- **Live dimensions readout:** the selection size (e.g. `640 × 480`) shows near the selection (top-left)
  and updates while resizing.
- **Selection stays editable at any time:** the selection keeps **edge/corner handles** and can be
  **re-cropped or moved even after annotations exist**.
  - Annotations are anchored in **image/screen coordinates**. Re-cropping changes only which portion is
    exported: annotations (or parts of them) falling **outside** the new selection are **clipped on
    export**, not scaled or deleted; moving the selection re-reveals them.
- **Edge-aware placement:** the toolbar and any popover **reposition** to stay fully on-screen when the
  selection is near a display edge (e.g. flip above the selection when there's no room below).
- **Drawing interaction:** pick a tool → drag on the canvas to draw; shapes use the active color and
  thickness; the text tool places an editable text box at the click point.
- **Undo:** reverts the most recent annotation; supports a reasonable multi-step history.
- **Keyboard:** `Esc` cancels the whole capture; `⌘Z` = undo (nice-to-have).

> **Assets:** all toolbar/tool icons must be **original** to ahdishot (SF Symbols or custom art) — no
> Lightshot assets are reused.

---

## 5. Fixed color palette & tool defaults

- **Palette (CONFIRMED):** red, orange, yellow, green, blue, purple, black, white.
- **Default active color:** red.
- **Stroke thicknesses (CONFIRMED):** thin / medium / thick = **2 / 4 / 6 pt** at 1× (owner-confirmed
  2026-07-05). Default = medium (4 pt).
- **Text size (CONFIRMED approach):** the user **pre-selects** a size from a **wide preset range** —
  wider than the earlier 14–28 pt proposal — to cover both tiny detailed labels and large banners.
  Proposed presets: **8, 10, 12, 14, 18, 24, 36, 48, 72, 96 pt** (palette-colored, system font).
  - _Rationale:_ Lightshot resized text live via the **scroll wheel**, but live re-fitting of the text
    box inside the selection is fiddly; pre-selection avoids that complexity for v1.
  - _Future enhancement:_ optional scroll-wheel live resize once the editor is stable.

---

## 6. Non-functional requirements

### 6.1 Performance / resource budget (lightweight)
- **NFR-1** **Idle:** effectively **0% CPU** and minimal memory. The app is **event-driven** (registered
  hotkey + menu bar), with **no polling loops, no timers, no background network**.
- **NFR-2** Target **idle memory footprint < ~30 MB**; cold-launch to hotkey-ready quickly.
- **NFR-3** No network access at all in v1 (no uploads, telemetry, or update checks).
- **NFR-4** Capture-to-editor latency should feel instantaneous (well under ~200 ms for typical regions).

### 6.2 Reliability
- **NFR-5** Must capture **any** on-screen content, including full-screen video and games (still frame at
  press time). Uses `ScreenCaptureKit` which captures composited display output.
- **NFR-6** Graceful handling if **Screen Recording permission** is not yet granted (guide the user to
  grant it; retry).

### 6.3 Security & privacy
- **NFR-7** No data leaves the device. No analytics.
- **NFR-8** Screenshots are written only to the user-chosen folder.
- **NFR-9** Requests only the permissions it needs (Screen Recording; see §7).

---

## 7. Permissions

| Permission | Needed for | When requested |
|---|---|---|
| **Screen Recording** (TCC) | Capturing display pixels via `ScreenCaptureKit` | On first capture attempt |
| **Accessibility** | _Not required_ — global hotkey uses `RegisterEventHotKey`, which does not need it | — |
| **Login item** | Launch at login | When the user enables it (`SMAppService`) |

---

## 8. Technical architecture (implementation notes)

- **Language / UI:** Swift 6 + **AppKit**, built **programmatically** (no storyboards/xibs — full Xcode
  is not installed; build via command-line toolchain). Native `arm64`.
- **Capture:** `ScreenCaptureKit` (`SCScreenshotManager`, macOS 14+) for still capture of composited
  display output; per-display `SCDisplay` handling for multi-monitor and correct DPI.
- **Region overlay:** borderless, transparent, full-screen-per-display `NSWindow`(s) at a high window
  level for the drag-select UI.
- **Global hotkey:** Carbon `RegisterEventHotKey` (native `arm64`, no Accessibility permission,
  sandbox-compatible).
- **Launch at login:** `SMAppService.mainApp` (macOS 13+).
- **Settings:** `UserDefaults` (or app-group defaults under sandbox).
- **Editor:** custom `NSView` canvas; annotations as an ordered list of drawable objects (undo = pop);
  flatten to `CGImage`/`NSBitmapImageRep` on export (PNG/JPG).
- **Build:** command-line Swift compile + hand-assembled `.app` bundle with `Info.plist`
  (`LSUIElement = true` so there's no Dock icon; menu bar only) and usage-description strings.
- **Distribution target:** macOS 15+.

---

## 9. App Store & distribution scoping

> Not shipping immediately, but design so it's achievable without rework.

- **Sandboxing:** App Store requires the **App Sandbox**. The chosen stack is compatible:
  - `ScreenCaptureKit` works sandboxed (user grants Screen Recording).
  - `RegisterEventHotKey` works sandboxed.
  - `SMAppService` login-item works sandboxed.
  - Saving to `~/Pictures/ahdishot` needs either the **user-selected-folder** entitlement (via a
    security-scoped bookmark chosen once in Settings) or writing within the app container. **Design the
    save-folder picker to produce a security-scoped bookmark** so this is App-Store-ready.
- **Signing / notarization:** requires a paid **Apple Developer Program** membership ($99/yr). For direct
  distribution: Developer ID signing + **notarization** + hardened runtime. For App Store: distribution
  provisioning profile + App Store Connect listing.
- **Hardened runtime:** enable; declare entitlements minimally.
- **Privacy:** App Store **privacy nutrition label** = "no data collected" (true here). Provide a short
  privacy policy URL (can state no collection).
- **Licensing:** **proprietary/closed** source; owner retains all rights. Ship an EULA. (Confirm no
  third-party code with incompatible licenses is bundled — currently none planned.)
- **Pricing:** free or one-time paid — both are straightforward App Store models; no server needed.
- **Do NOT** reuse any Lightshot assets (icons/strings/images). All UI assets for ahdishot must be
  **original** to avoid IP issues. Menu bar / app icon: original artwork or SF Symbols.

---

## 10. Phased delivery plan

Each phase is **run and verified on-device**, not just compiled.

- **Phase 1 — Native core loop:** hotkey (⌘1) → multi-display drag-select overlay → capture via
  ScreenCaptureKit → **Copy to clipboard + auto-save PNG** to `~/Pictures/ahdishot`. Menu bar icon with
  Quit. Proves native capture works end-to-end. _(No annotation yet.)_
- **Phase 2 — Annotation editor:** inline Lightshot-style toolbar + full tool set (rectangle, ellipse,
  arrow, line, pencil, marker, text), fixed palette, thickness, undo; Copy/Save/Close actions.
  _(Refine §4 with owner's UI description first.)_
- **Phase 3 — Settings & polish:** Settings window (hotkey, save folder, format, launch-at-login,
  default color/thickness), `SMAppService` login item, multi-monitor/Retina correctness, JPG option.
- **Phase 4 — Distribution readiness (when desired):** sandbox entitlements + security-scoped bookmark
  for save folder, signing, notarization, App Store Connect listing, EULA + privacy policy.

---

## 11. Open questions / TBD

1. ~~**Stroke thickness steps**~~ — **RESOLVED 2026-07-05:** thin/medium/thick = **2 / 4 / 6 pt** (§5).
2. **App / menu-bar icon** — placeholder SF Symbol for now; commission original artwork before release.
3. **Apple Developer Program** — owner to enroll before any signed/App Store build (Phase 4).
