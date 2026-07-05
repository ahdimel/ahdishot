# ahdishot — Phase 1 Handover

> For the next agent/developer picking this up. Pairs with **[REQUIREMENTS.md](REQUIREMENTS.md)** (the
> source of truth for scope & decisions). This doc covers **what Phase 1 delivered, how it's built, what
> is verified vs. still needs a human smoke-test, and where Phase 2 starts.**
>
> **Date:** 2026-07-05 · **Status:** Phase 1 code complete; builds & launches natively on arm64.

---

## 1. What Phase 1 is

The native-capture core loop, proving the whole arm64 pipeline works end-to-end **before** any annotation
UI is built:

**Global hotkey (⌘1) → dimmed multi-display drag-select overlay → ScreenCaptureKit grab at native
resolution → crop → copy to clipboard + auto-save PNG to `~/Pictures/ahdishot/`.**

Plus a menu-bar agent (no Dock icon) with **Capture Region**, **Open Screenshots Folder**, and **Quit**.

> Note: Phase 1 does **both** copy *and* save on capture purely to demonstrate the pipeline without an
> editor. Per [REQUIREMENTS.md](REQUIREMENTS.md) §2, the shipping behavior is that Copy and Save are
> **separate buttons** in the Phase 2 inline editor — revisit this when the editor lands.

---

## 2. Verified vs. not yet verified

| Check | Status |
|---|---|
| Compiles to native **arm64** (no Rosetta) | ✅ `file` reports `Mach-O 64-bit executable arm64` |
| Launches as a menu-bar agent, no crash | ✅ runs; menu bar icon present; no Dock icon |
| Idle resource use | ✅ **~40 MB RSS, 0.0% CPU** (event-driven, no polling) |
| Hotkey registration (Carbon) | ✅ registers at launch without error |
| **End-to-end capture (permission + drag + save)** | ✅ **Smoke-tested 2026-07-05** (owner) — permission grant, drag-select, crisp Retina PNG saved, works over a full-screen game (Factorio). See §6.1. |

**The interactive capture path could not be exercised headlessly** (it requires the macOS Screen
Recording TCC grant and a real mouse drag). Everything up to that point is verified. First human run should
follow the checklist in §6.

---

## 3. Project layout

```
ahdishot/
├── REQUIREMENTS.md          # Scope & decisions (source of truth)
├── HANDOVER.md              # This file
├── build.sh                 # Compile + assemble + ad-hoc sign the .app
├── .gitignore               # ignores build/ and .DS_Store
├── Sources/
│   ├── main.swift           # Entry point; NSApplication + .accessory policy
│   ├── AppDelegate.swift    # Menu bar, hotkey wiring, capture orchestration, error UI
│   ├── HotKeyManager.swift  # Carbon RegisterEventHotKey wrapper
│   ├── SelectionOverlay.swift # Overlay windows + drag-select view + dimensions readout
│   └── ScreenCapturer.swift # ScreenCaptureKit grab, crop, clipboard, PNG save
├── Resources/
│   └── Info.plist           # Bundle id com.ahdimel.ahdishot, LSUIElement, min macOS 15
└── build/                   # (generated) ahdishot.app lives here
```

No Xcode project — the app is built entirely from the command line with `swiftc` (only the Command Line
Tools are installed on this machine, not full Xcode).

---

## 4. How to build & run

```bash
cd /Users/ahdimel/Documents/vscode/ahdishot
./build.sh                      # -> build/ahdishot.app  (arm64, ad-hoc signed)
open build/ahdishot.app         # launches the menu-bar agent
```

To stop it: use the menu bar ▸ **Quit ahdishot**, or `pkill -x ahdishot`.

**Toolchain:** Swift 6.1.2 (Command Line Tools), macOS 15+ deployment target, frameworks: Cocoa,
ScreenCaptureKit, Carbon, UniformTypeIdentifiers.

---

## 5. Architecture notes (read before editing capture code)

- **Hotkey** (`HotKeyManager`): Carbon `RegisterEventHotKey` on the application event target. Native
  arm64, **no Accessibility permission**, sandbox-friendly. Default keyCode `kVK_ANSI_1` + `cmdKey`.
  The C event-handler callback recovers `self` via an `Unmanaged` opaque pointer.
- **Overlay** (`SelectionOverlayController` + `SelectionView`): one borderless, transparent,
  `.screenSaver`-level `NSWindow` **per `NSScreen`**, with `collectionBehavior` including
  `.canJoinAllSpaces`/`.fullScreenAuxiliary` so it can appear over full-screen apps. The view fills the
  screen with 35% black, then **punches a transparent hole** for the selection using
  `.clear` compositing, and draws the border + a **pixel** dimensions readout.
- **Coordinate handling (the tricky part):**
  - `SelectionView` is **non-flipped** (bottom-left origin), so `selectionRect` is in the screen's local
    **points, bottom-left origin**.
  - `ScreenCapturer.capture` converts to the captured CGImage's **pixel, top-left origin** space:
    `yTop = screen.frame.height - (rect.origin.y + rect.height)`, then multiplies all values by
    `screen.backingScaleFactor` for Retina.
  - Selection is assumed to be **within a single display** (the one the drag happened on). Cross-display
    selections are not handled in Phase 1.
- **Capture** (`ScreenCapturer`): maps `NSScreen` → `SCDisplay` by `displayID`
  (`NSScreenNumber`), grabs the full display via `SCScreenshotManager.captureImage` at
  `frame.size * scale` with `captureResolution = .best`, then `CGImage.cropping(to:)`.
  A **100 ms sleep** before capture lets the overlay windows leave the screen composite so they don't
  appear in the shot.
- **Output** (`ScreenCapturer`): PNG via `NSBitmapImageRep`; clipboard via `NSPasteboard` (writes an
  `NSImage` plus explicit PNG data). Save dir `~/Pictures/ahdishot/`, filename
  `ahdishot_yyyy-MM-dd_at_HH.mm.ss.png`.

---

## 6. First-run smoke-test checklist (do this next)

1. `./build.sh && open build/ahdishot.app` — confirm the **camera.viewfinder** icon appears in the menu bar.
2. Press **⌘1** (or menu ▸ Capture Region). The screen should dim with a crosshair cursor.
   - On the very first capture, macOS will prompt for **Screen Recording** permission (or the app shows an
     alert with an **Open Settings** button). Grant it under **System Settings ▸ Privacy & Security ▸
     Screen Recording**, then **relaunch** the app and try again (TCC grants take effect on relaunch).
3. Drag a region and release. Verify:
   - A PNG appears in `~/Pictures/ahdishot/` (menu ▸ Open Screenshots Folder).
   - The image is on the clipboard (⌘V into Preview/Notes) and is **crisp at Retina resolution**.
   - The captured region matches the selection (no off-by-scale/flip errors).
4. Press **Esc** during selection → cancels cleanly, nothing saved.
5. If you have **multiple monitors**, test a selection on the secondary display (correct crop + scale).
6. Test over **full-screen video/a game** (still frame at press time) — this is a requirement; confirm the
   overlay appears and the grab succeeds. (See known-risk note in §7.)

---

### 6.1 Smoke-test results (2026-07-05, owner)

Ran on the owner's M4 Mac, macOS 26.5:

- ✅ Screen Recording permission granted; capture works.
- ✅ Hotkey opens a selection area that tracks the cursor.
- ✅ Drag + click commits the selection, auto-closes the overlay, and saves.
- ✅ A crisp high-res PNG is saved to `~/Pictures/ahdishot/` as intended.
- ✅ Works over a **full-screen video game (Factorio)** — the §7 full-screen-Space risk did **not**
  materialize here. (Still worth keeping in mind for other full-screen apps.)
- ❌ **Esc does not cancel** the selection — see §7 (this is a bug, not just the auto-commit behavior).

## 7. Known limitations / risks to watch

- **Esc doesn't cancel the selection (BUG).** `SelectionView.keyDown` handles Esc (keyCode 53), but the
  borderless overlay window almost certainly isn't becoming key / first responder, so the keystroke never
  reaches the view. Fix in Phase 2: make the overlay window `canBecomeKey == true` (subclass `NSWindow`
  overriding `canBecomeKey`) and set the view as `initialFirstResponder` / call
  `makeFirstResponder(view)` after `makeKey`. (Note: once Phase 2 shows an inline editor instead of
  auto-committing on mouseUp, Esc/cancel semantics change anyway — wire cancel there too.)

- **Full-screen Spaces:** the overlay uses `.canJoinAllSpaces` + `.fullScreenAuxiliary`, but showing a
  selection overlay over another app's *dedicated full-screen Space* is historically finicky on macOS.
  Verify step 6 above; if the overlay doesn't appear there, we may need an alternative (e.g., capture
  first, then annotate over a frozen snapshot) — worth designing into Phase 2 anyway.
- **Cross-display selections** are not supported (single display per capture).
- **Idle memory ~40 MB** vs. the aspirational <30 MB in REQUIREMENTS §6 (NFR-2). Much is shared framework
  memory; revisit if it matters, but it's normal for an AppKit agent.
- **Ad-hoc signing:** fine for local dev. A Screen Recording grant may need re-approval after some
  rebuilds because ad-hoc signatures aren't stable. For distribution this is replaced by Developer ID /
  App Store signing (REQUIREMENTS §9).
- **No settings/persistence yet** (hotkey, save folder, format are hardcoded). That's Phase 3.
- **No launch-at-login yet** (`SMAppService`). Phase 3.

---

## 8. Where Phase 2 starts (annotation editor)

Build the **inline editor** per **[REQUIREMENTS.md](REQUIREMENTS.md) §4** (all confirmed):

- Replace "capture → immediately copy+save" with "capture → **show inline editor** over the frozen
  selection." A clean approach given the full-screen-Space risk: on commit, **grab the CGImage first**,
  then present an editor window showing that image, with the toolbar attached below the selection.
- **Single combined bottom toolbar:** draw tools (rectangle, ellipse, arrow, line, pencil, marker, text,
  undo) + separator + actions (copy, save, close). Icons must be **original** (SF Symbols ok) — no
  Lightshot assets.
- **Tool-options popover** on tool select: fixed palette swatches (§5) + thickness steps
  (thin/med/thick ≈ 2/4/6 pt) + text-size presets (8–96 pt, §5).
- Annotations as an ordered list of drawable objects (undo = pop); **flatten to CGImage on export**.
- Selection stays **re-croppable/movable**; annotations anchored in image coords, **clipped (not scaled)**
  on export.
- Wire **Copy** and **Save** as the separate actions they're meant to be (drop the Phase 1 "do both").

Then **Phase 3** (settings window, `SMAppService` launch-at-login, JPG option, hotkey config) and
**Phase 4** (sandbox entitlements + security-scoped bookmark for save folder, signing, notarization, App
Store) per REQUIREMENTS §9–§10.

---

## 9. Quick reference — key files & symbols

- Change the **hotkey default**: `AppDelegate.applicationDidFinishLaunching` (`kVK_ANSI_1`, `cmdKey`).
- Change **save location / format / filename**: `ScreenCapturer.saveDirectory` / `savePNG` / `timestamp`.
- Change **overlay look** (dim level, border, dimensions): `SelectionView.draw` / `drawDimensions`.
- Change **capture/crop math**: `ScreenCapturer.capture`.
- Menu bar items: `AppDelegate.setupStatusItem`.
