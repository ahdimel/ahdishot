# ahdishot — Handover (through Phase 3)

> For the next agent/developer picking this up. Pairs with **[REQUIREMENTS.md](REQUIREMENTS.md)** (the
> source of truth for scope & decisions). This doc covers **what Phases 1–3 delivered, how it's built,
> what is verified vs. still needs a human smoke-test, and where Phase 4 starts.**
>
> **Date:** 2026-07-05 · **Status:** Phases 1–3 **fully owner-verified on-device** (native arm64). Phase 3
> (Settings & polish): Settings window, hotkey recorder incl. Clear/no-hotkey, reject-beep, PNG/JPG, folder
> picker, default color/thickness, **persistence across relaunch**, and **launch-at-login confirmed across a
> real reboot** (auto-boots with settings intact) — see §12.1. Phase 2 = the inline annotation editor (§0).
> Only **multi-monitor** remains unexercised across all phases. Ready for Phase 4 (§9).

---

## -1. Phase 3 at a glance (newest work)

A **Settings window** and the persistence/login-item polish from REQUIREMENTS §3.4–§3.5:

- **Menu bar** now has **Settings…** (⌘,) and a checkable **Launch at Login** item (check state refreshes
  on menu-open via `NSMenuDelegate`).
- **Settings window** (`SettingsWindowController`, programmatic AppKit, no xib): global **hotkey recorder**,
  **save folder** picker, **image format** (PNG/JPG) popup, **launch at login** checkbox, default annotation
  **color** (palette swatches) + **thickness** (Thin/Medium/Thick). Writes straight through to `Settings`.
- **Persistence** (`Settings`, `UserDefaults`): hotkey code+modifiers, save-folder **bookmark**, format,
  default color index, default thickness. Registered defaults = ⌘1 / PNG / red / medium.
- **Global hotkey is now driven by the setting** and **re-registers live** when changed (via the
  `Settings.hotKeyChanged` notification → `AppDelegate.registerHotKey`).
- **Hotkey is optional** — the recorder has a **Clear** button; cleared = **no global hotkey** (capture
  only via the menu bar's Capture Region). "None" is stored as **zero modifiers** (not keyCode 0, which is
  a real key — `kVK_ANSI_A`); `Settings.hasHotKey` gates registration. The recorder shows "Click to set…"
  when cleared. Recording **requires ≥1 modifier** (bare key ⇒ beep) so a shortcut can't hijack a plain key.
- **Launch at login** = `SMAppService.mainApp` (`LaunchAtLogin`); links the **ServiceManagement** framework.
- **Save honors format + folder**: `ScreenCapturer.savePNG` → **`ScreenCapturer.save`** (PNG or JPEG@0.9),
  `saveDirectory()` resolves the configured folder. **Clipboard stays PNG** regardless of format.
- **Editor defaults**: `EditorView` seeds every tool's color/thickness from `Settings` (then per-tool
  memory takes over as before).

New files: `Settings.swift`, `LaunchAtLogin.swift`, `HotKeyRecorderButton.swift`,
`SettingsWindowController.swift`. Changed: `AppDelegate.swift`, `ScreenCapturer.swift`, `EditorView.swift`,
`EditorWindowController.swift`, `build.sh` (+ServiceManagement). Build/run unchanged (`./build.sh`).

**Save-folder is App-Store-ready by design:** it's stored as a **bookmark** produced by the NSOpenPanel
picker. Phase 4 only swaps `bookmarkData()`/`URL(resolvingBookmarkData:)` for their `.withSecurityScope`
variants once the sandbox `user-selected.read-write` entitlement exists — see `Settings.swift` header.

---

## 0. Phase 2 at a glance (newest work)

The "immediately copy+save" of Phase 1 is **gone**; capture now opens a **Lightshot-style inline
editor**:

**⌘1 → drag-select → grab the whole display as a frozen frame → editor window: crisp selection over a
dimmed backdrop, a combined bottom toolbar, annotate in place → Copy / Save / Close.**

- **Draw tools:** rectangle, ellipse, arrow, line, pencil, marker (translucent), text, undo. Each tool
  opens a **popover** with the 8-color palette + thickness (2/4/6 pt) + (text) size presets, remembered
  per tool.
- **Selection stays re-croppable/movable** via edge/corner handles; annotations are anchored in image
  space and **clipped (not scaled)** on export. This is why capture grabs the **full display**, not just
  the drag rect — see §5.1.
- **Copy** and **Save** are now the separate actions from REQUIREMENTS §2/§3.3; **both dismiss** the
  editor after acting (owner decision); **Close/Esc** dismiss with nothing written.
- Phase 1's **Esc-cancel bug is fixed** (§7) via `KeyableWindow`.

New files: `KeyableWindow.swift`, `Annotation.swift`, `EditorView.swift`, `EditorToolbar.swift`,
`EditorWindowController.swift`. Changed: `ScreenCapturer.swift`, `SelectionOverlay.swift`,
`AppDelegate.swift`. Build/run is unchanged (`./build.sh`; files stay flat in `Sources/`).

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
| **Phase 2 — compiles clean (no warnings), arm64** | ✅ `./build.sh` succeeds; `file` reports arm64. |
| **Phase 2 — launches, idle footprint** | ✅ launches as before; **~43 MB RSS, 0.0% CPU** idle. |
| **Phase 2 — full editor (annotate / palette / text / copy / save / undo / resize / re-crop-clip / esc / edge-flip)** | ✅ **Owner-verified 2026-07-05** — see §10.1. |
| **Phase 3 — compiles clean (no warnings), arm64** | ✅ `./build.sh` succeeds; `file` reports arm64. |
| **Phase 3 — launches, idle footprint** | ✅ launches as before; **~43 MB RSS, 0.0% CPU** idle. |
| **Phase 3 — Settings window / hotkey recorder (+Clear) / reject-beep / JPG / folder picker / defaults / persistence** | ✅ **Owner-verified 2026-07-05** — see §12.1. |
| **Phase 3 — launch-at-login survives an actual reboot** | ✅ **Owner-verified 2026-07-05** — app auto-boots after restart with all settings intact. |

**The interactive paths cannot be exercised headlessly** (they need the macOS Screen Recording TCC grant
and real mouse input). The owner smoke-tested the whole editor on-device (§10.1). Only **multi-monitor**
remains unexercised (single-display setup at test time; low risk).

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
│   ├── AppDelegate.swift    # Menu bar, hotkey wiring, capture → editor orchestration, error UI
│   ├── HotKeyManager.swift  # Carbon RegisterEventHotKey wrapper
│   ├── KeyableWindow.swift  # Borderless NSWindow that can become key (overlay + editor; fixes Esc)
│   ├── SelectionOverlay.swift # Overlay windows + drag-select view + dimensions readout
│   ├── ScreenCapturer.swift # ScreenCaptureKit full-display grab, crop, clipboard, PNG/JPG save (per Settings)
│   ├── Annotation.swift     # Non-destructive drawable objects (rect/ellipse/arrow/line/pencil/marker/text)
│   ├── EditorView.swift     # Editor canvas: backdrop, selection edit, drawing, text, flatten() + Tool/Palette
│   ├── EditorToolbar.swift  # Combined bottom toolbar + per-tool options popover
│   ├── EditorWindowController.swift # Hosts the editor window; wires Copy/Save/Close
│   ├── Settings.swift       # UserDefaults model: hotkey, save-folder bookmark, format, default color/thickness
│   ├── LaunchAtLogin.swift  # SMAppService.mainApp login-item wrapper
│   ├── HotKeyRecorderButton.swift # Click-to-record shortcut control (keyCode+modifier capture)
│   └── SettingsWindowController.swift # Settings window (programmatic AppKit)
├── tools/
│   └── make-icon.swift      # Regenerates Resources/AppIcon.icns (SF Symbol on a gradient squircle)
├── Resources/
│   ├── Info.plist           # Bundle id com.ahdimel.ahdishot, LSUIElement, CFBundleIconFile, min macOS 15
│   └── AppIcon.icns         # Generated app icon (see §13 / tools/make-icon.swift)
└── build/                   # (generated) ahdishot.app lives here
```

No Xcode project — the app is built entirely from the command line with `swiftc` (only the Command Line
Tools are installed on this machine, not full Xcode).

---

## 4. How to build & run

```bash
cd /Users/ahdimel/Documents/vscode/ahdishot
./build.sh                      # -> build/ahdishot.app  (arm64, signed with ahdishot-dev)
open build/ahdishot.app         # launches the menu-bar agent
```

To stop it: use the menu bar ▸ **Quit ahdishot**, or `pkill -x ahdishot`.

**Toolchain:** Swift 6.1.2 (Command Line Tools), macOS 15+ deployment target, frameworks: Cocoa,
ScreenCaptureKit, Carbon, UniformTypeIdentifiers.

### 4.1 Local code-signing identity (why rebuilds no longer nuke the Screen Recording grant)

`build.sh` signs with a **stable self-signed identity** named **`ahdishot-dev`** in the login keychain,
falling back to ad-hoc (`-`) if it's absent. This matters because macOS ties the **Screen Recording (TCC)**
grant to the app's *designated requirement*. With ad-hoc signing the requirement is the raw **cdhash**,
which changes on **every build**, so each rebuild looked like a new app and dropped the grant (you'd
re-approve constantly, and a stale "ahdishot" entry would linger in Settings). Signing with `ahdishot-dev`
makes the requirement `identifier "com.ahdimel.ahdishot" and certificate leaf = H"<cert hash>"` — stable
across rebuilds, so **the grant persists**. (This is a *local dev* convenience; Phase 4 replaces it with
Developer ID / App Store signing per REQUIREMENTS §9.)

**Recreate the identity** (new machine, or if the keychain entry is deleted) — one-liner, no Xcode/GUI:

```bash
CN=ahdishot-dev
openssl req -x509 -newkey rsa:2048 -keyout k.pem -out c.pem -days 3650 -nodes \
  -subj "/CN=$CN" -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning"
openssl pkcs12 -export -legacy -inkey k.pem -in c.pem -out "$CN.p12" -passout pass:$CN -name "$CN"
security import "$CN.p12" -k ~/Library/Keychains/login.keychain-db -P "$CN" -A -T /usr/bin/codesign
rm k.pem c.pem "$CN.p12"      # key now lives in the keychain
```

Notes: `-legacy` is required (Apple can't read OpenSSL-3 default PKCS12 MAC). The cert is **untrusted**,
which is fine — `codesign` signs by name and TCC matches on the requirement, neither needs trust. After
recreating, the *first* grant must be re-done once (the new cert has a new leaf hash). To wipe a stale
grant during testing: `tccutil reset ScreenCapture com.ahdimel.ahdishot`, then relaunch and re-grant.

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

- **Esc-cancel bug — FIXED in Phase 2.** Root cause was as suspected: the borderless overlay window
  wasn't becoming key, so `keyDown` never reached the view. Fix: `KeyableWindow` (overrides
  `canBecomeKey`) is now used for both the overlay and the editor, and the controllers call
  `makeFirstResponder(view)` after `makeKey`. **Owner should re-confirm** Esc cancels the overlay and
  closes the editor during the §10 pass.

- **Text-annotation placement is approximate.** The temporary `NSTextField` used for entry has a small
  internal inset, so the committed text may sit ~2–3 pt off from where it was typed (a fixed nudge is
  applied in `EditorView.commitActiveText`). Fine for v1; tighten with an `NSTextView` + real layout
  metrics if it bothers the owner. Text entry is also **single-line**.

- **Full-screen Spaces:** the overlay uses `.canJoinAllSpaces` + `.fullScreenAuxiliary`, but showing a
  selection overlay over another app's *dedicated full-screen Space* is historically finicky on macOS.
  Verify step 6 above; if the overlay doesn't appear there, we may need an alternative (e.g., capture
  first, then annotate over a frozen snapshot) — worth designing into Phase 2 anyway.
- **Cross-display selections** are not supported (single display per capture).
- **Idle memory ~40 MB** vs. the aspirational <30 MB in REQUIREMENTS §6 (NFR-2). Much is shared framework
  memory; revisit if it matters, but it's normal for an AppKit agent.
- **Code signing:** now a **stable self-signed `ahdishot-dev`** identity (see §4.1) so the Screen
  Recording grant survives rebuilds; `build.sh` falls back to ad-hoc only if that cert is missing. The
  identity is machine-local (login keychain) — a fresh checkout on another Mac must recreate it (§4.1)
  and grant once. For distribution this is replaced by Developer ID / App Store signing (REQUIREMENTS §9).
- **No settings/persistence yet** (hotkey, save folder, format are hardcoded). That's Phase 3.
- **No launch-at-login yet** (`SMAppService`). Phase 3.

---

## 8. Phase 2 editor architecture (read before editing editor code)

- **Capture the FULL display, then edit (§5.1).** On commit, `AppDelegate.handleSelection` calls
  `ScreenCapturer.captureFullDisplay(screen:)` (the old `capture` minus the crop) and hands the whole
  frozen display image to `EditorWindowController`. Grabbing the full display — not just the drag rect —
  is what makes the selection **re-croppable/movable** inside the editor; you can't re-expand a crop you
  never captured. It also grabs the frozen frame *before* any editor UI appears, sidestepping the
  full-screen-Space overlay risk. Cost: a transient ~30 MB CGImage held only while the editor is open.
- **Coordinates:** `EditorView` is **non-flipped**, its point space is 1:1 with `NSScreen`. Annotations
  store geometry in that space, so moving/resizing the selection never moves them. Export
  (`EditorView.flatten`) crops via `ScreenCapturer.crop(_:screen:localRect:)` (shared point→pixel/
  top-left math), then re-draws annotations translated into crop space and **clipped** to the selection —
  matching "clipped, not scaled, on export."
- **Annotations** (`Annotation.swift`): a protocol with `draw()`; the same code paints the live view and
  the flatten bitmap. `TwoPointAnnotation` base (rectangle/ellipse/line/arrow), `FreehandAnnotation`
  (pencil; also marker with translucent color + 4× width so a single path keeps uniform alpha),
  `TextAnnotation`. Ordered list on `EditorView`; **undo = removeLast** (⌘Z or the toolbar button).
- **Interaction** (`EditorView`): hit-test **handles/border first** (always resize/move, any tool), else
  an interior drag draws with the active tool. Text tool click places a temporary `NSTextField`; commit
  on Enter or click-away. `Tool`, `Palette`, `thicknessSteps`, `textSizePresets`, `ToolSettings` live at
  the top of `EditorView.swift`.
- **Toolbar** (`EditorToolbar.swift`): a **subview** of the canvas (same coord space — no second window
  to sync), manually laid out, repositioned by `reposition(around:in:)` to sit below the selection and
  flip/clamp on-screen. Selecting a draw tool opens an `NSPopover` (`ToolOptionsController`) with the 8
  swatches + thickness segmented control + (text) size popup; settings are remembered **per tool**.
  Icons are original **SF Symbols** (no Lightshot assets). Copy/Save call `flatten()` →
  `ScreenCapturer.copyToClipboard` / `save`, then dismiss.

## 8.5 Phase 3 architecture (read before editing settings code)

- **`Settings`** (singleton over `UserDefaults`) is the one source of truth for hotkey, save folder,
  format, default color/thickness. It `register(defaults:)`s the shipping defaults (⌘1 / PNG / red /
  medium) so a fresh install behaves like Phases 1–2. Changing the hotkey posts `Settings.hotKeyChanged`;
  `AppDelegate.registerHotKey` observes it and re-registers the Carbon hotkey **live** (no relaunch).
- **Save folder is a bookmark, not a path** — see the §-1 note and the `Settings.swift` header. This is the
  deliberate App-Store seam: the picker already yields the bookmark; Phase 4 flips two options to
  `.withSecurityScope`.
- **`LaunchAtLogin`** wraps `SMAppService.mainApp`; its `status` **is** the state (nothing mirrored in
  `UserDefaults`). Registration can throw (translocated/quarantined path) — both the menu item and the
  Settings checkbox catch, alert, and revert. Links the **ServiceManagement** framework (`build.sh`).
- **`HotKeyRecorderButton`** records via a **local `NSEvent` monitor** (returns `nil` to swallow the combo
  so it doesn't trigger menu/app shortcuts). Requires ≥1 modifier (a bare global key would shadow it in
  every app); `Esc` cancels. Converts `NSEvent.ModifierFlags` → Carbon mask; virtual-keycode→label table
  is `keyNames`.
- **`SettingsWindowController`** is programmatic AppKit (no xib), reused across opens, `syncFromSettings()`
  on each show. Every control writes straight through to `Settings`/`LaunchAtLogin` — no Apply/OK button.
- **`ScreenCapturer.save`** replaced `savePNG`: encodes PNG or **JPEG@0.9** per `Settings.imageFormat`;
  filename extension follows. **Clipboard stays PNG** (lossless, universally pasteable). `EditorView`
  seeds each tool's color/thickness from `Settings` at construction, then per-tool memory takes over.

## 9. Where Phase 4 starts (distribution readiness) — ON HOLD

> ⚠️ **Phase 4 is blocked by owner decision (2026-07-05): NOT enrolling in the Apple Developer Program
> yet.** No Developer ID cert ⇒ **no notarization and no App Store** (REQUIREMENTS §9 callout). The app is
> **local-only** for now: signed with the self-signed `ahdishot-dev` identity (§4.1) and **installed by
> hand into `/Applications`** (see §13). Everything below waits until the owner opts to enroll ($99/yr).

**Phase 4** per **[REQUIREMENTS.md](REQUIREMENTS.md) §9**: App **Sandbox** entitlements + the
**security-scoped bookmark** flip for the save folder (the seam is already in `Settings.swift` — swap
`bookmarkData()`/`URL(resolvingBookmarkData:)` to `.withSecurityScope`), **Developer ID signing +
notarization + hardened runtime**, App Store Connect listing, EULA + privacy policy, and **bespoke app
artwork** to replace the generated placeholder icon (§13).

Nice-to-haves still open: **multi-monitor** verification (never exercised), tighter text placement (§7),
scroll-wheel live text resize (REQUIREMENTS §5), and cross-display selection.

---

## 10. Phase 2 first-run smoke-test checklist (do this next)

Prereq: Screen Recording already granted from Phase 1 (re-grant if an ad-hoc rebuild invalidated it).

1. `./build.sh && open build/ahdishot.app`; press **⌘1**, drag a region → the **editor** appears
   (crisp selection, dimmed surround, bottom toolbar) instead of an instant save.
2. **Each draw tool** — rectangle, ellipse, arrow, line, pencil, marker: draw one; open its popover and
   change **color** + **thickness** and confirm they apply and are **remembered per tool** when you
   switch tools and back.
3. **Text:** pick the text tool, click, type, choose a **size** + color, press Enter → text lands.
4. **Undo:** the toolbar undo button and **⌘Z** both pop the last annotation, in order.
5. **Re-crop/move:** drag the selection's handles/border after annotating → annotations stay anchored;
   parts moved outside the new crop are **excluded on export** (not scaled/deleted).
6. **Save** → timestamped PNG in `~/Pictures/ahdishot/`, flattened + crisp at Retina; editor dismisses.
   **Copy** → ⌘V into Preview shows the flattened image; editor dismisses. **Close** and **Esc** →
   dismiss with nothing written.
7. **Toolbar edge-awareness:** select near the bottom/side edges → the toolbar flips above / clamps
   on-screen.
8. **Idle after close:** confirm RSS/CPU return to ~40 MB / 0% (no leaked editor window or retained
   full-display image).

### 10.1 Smoke-test results (2026-07-05, owner)

On the owner's M4 Mac, editor signed with `ahdishot-dev`:

- ✅ **Draw tools:** pencil, highlighter/marker, arrow, rectangle, ellipse all work.
- ✅ **Color palette** applies; **text boxes** work with different font sizes.
- ✅ **Copy to clipboard**, **undo**, and **resize/re-crop the selection box** all work.
- ✅ **Fixed:** the text tool's options popover no longer shows a dead "thickness" control (thickness is
  stroke-only; text uses the size popup). Verified after rebuild.
- ✅ **Save** to `~/Pictures/ahdishot/`, **Esc** closes the editor, toolbar **edge-flip** on both edges.
- ✅ **Re-crop clipping on export:** resizing the crop leaves annotations anchored in place; parts outside
  the box show dimmed and are clipped (not scaled/deleted) on export — moving the box back re-reveals them.
- ✅ **Signed with the stable `ahdishot-dev` identity** (§4.1); Screen Recording grant now persists across
  rebuilds.
- ⏳ **Multi-monitor** not exercised (single-display setup at test time); low risk.

---

## 11. Quick reference — key files & symbols

- Change the **hotkey default** (fresh-install value): `Settings.init` registered defaults (`kVK_ANSI_1`,
  `cmdKey`). The live hotkey is read from `Settings.hotKeyCode/Modifiers` in `AppDelegate.registerHotKey`.
- Change **save location / format / filename**: `Settings.saveFolderURL` / `ScreenCapturer.save` +
  `ScreenCapturer.encode` / `ScreenCapturer.timestamp`.
- Change **default color/thickness/format defaults**: `Settings.init` registered defaults.
- Change the **Settings window** (rows, controls, layout): `SettingsWindowController`.
- Change the **hotkey recorder** (key labels, modifier rules): `HotKeyRecorderButton` (`keyNames`, `handle`).
- Change **launch-at-login** behavior: `LaunchAtLogin` (`SMAppService.mainApp`).
- Change **overlay look** (dim level, border, dimensions): `SelectionView.draw` / `drawDimensions`.
- Change **full-display capture / crop math**: `ScreenCapturer.captureFullDisplay` / `crop(_:screen:localRect:)`.
- Change **palette / thickness / text sizes**: constants at the top of `EditorView.swift`
  (`Palette.colors`, `thicknessSteps`, `textSizePresets`).
- Change a **tool's drawing** (arrowhead size, marker alpha/width, etc.): the relevant class in `Annotation.swift`.
- Change **toolbar layout / icons / popover**: `EditorToolbar.swift` (`toolOrder`, `makeButton`, `ToolOptionsController`).
- Change **Copy/Save/Close wiring** or editor window setup: `EditorWindowController.swift`.
- Menu bar items: `AppDelegate.setupStatusItem`.
- Change the **app icon**: edit `tools/make-icon.swift`, then regenerate (§13).

---

## 13. App icon & local install (Phase-3.5 polish, 2026-07-05)

**Icon.** `Resources/AppIcon.icns` is a **generated placeholder** — a blue→purple rounded-rect squircle
with a white `camera.viewfinder` SF Symbol (same motif as the menu bar). It's **original** art (SF Symbol
on a custom plate; no Lightshot assets), meant to be replaced by bespoke artwork before any public release
(REQUIREMENTS §11). Wired via `CFBundleIconFile=AppIcon` in `Info.plist`; `build.sh` copies the `.icns`
into `Contents/Resources`.

**Regenerate it** (no Xcode needed):
```bash
swift tools/make-icon.swift /tmp/AppIcon.iconset
iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
./build.sh
```

**Local install.** Since distribution is on hold (§9), the app is installed **by hand**:
```bash
./build.sh
pkill -x ahdishot; rm -rf /Applications/ahdishot.app
ditto build/ahdishot.app /Applications/ahdishot.app   # ditto preserves the code signature
open /Applications/ahdishot.app
```
Notes: the stable `ahdishot-dev` signature means the Screen Recording grant carries over to the
`/Applications` copy (same bundle id + cert). **After installing, re-toggle Launch at Login from the
`/Applications` copy** so the login item points at the installed app, not an old `build/` path. If the icon
looks stale in the Dock/Finder, `touch /Applications/ahdishot.app` (already done at install).

---

## 12. Phase 3 first-run smoke-test checklist (do this next)

`./build.sh && open build/ahdishot.app`, then:

1. **Menu bar:** open the menu → **Settings…** (⌘,) and **Launch at Login** are present.
2. **Settings window opens** and shows current values (hotkey `⌘1`, save folder `~/Pictures/ahdishot`,
   format PNG, red swatch ringed, thickness Medium).
3. **Hotkey recorder:** click it → "Type shortcut…" → press e.g. **⌥⇧2** → it displays `⌥⇧2`. Press the
   new combo from any app → capture starts. Press **⌘1** again to restore (or your preference). Confirm a
   **bare key with no modifier is rejected** (beep), and **Esc** while recording cancels (quietly — that's
   the cancel path, distinct from the beep).
3a. **Clear (no hotkey):** click **Clear** → recorder shows "Click to set…", the old shortcut no longer
   fires anywhere (it passes through to the frontmost app); capture still works via menu ▸ Capture Region.
   Set a new shortcut → re-registers live. Quit/relaunch while cleared → stays cleared.
4. **Save folder:** click **Choose…**, pick a different folder → capture+**Save** writes there. Point it
   back to `~/Pictures/ahdishot` (or wherever you want).
5. **Image format → JPG:** capture, **Save** → a `.jpg` lands (verify it opens). Switch back to PNG.
   Confirm **Copy** still puts a **PNG** on the clipboard regardless of format.
6. **Default color/thickness:** set default color = blue, thickness = Thick → open a new capture; the first
   draw tool starts **blue/thick** (per-tool memory still works after that).
7. **Launch at Login:** toggle it **on** (menu item checks; Settings checkbox agrees) → confirm ahdishot
   appears in **System Settings ▸ General ▸ Login Items**. Toggle **off** → it disappears. (If it throws,
   note the path — SMAppService dislikes translocated/quarantined app copies; run from a stable location.)
8. **Persistence:** Quit and relaunch → all settings above survived.
9. **Idle after close:** RSS/CPU back to ~40 MB / 0%.

### 12.1 Smoke-test results (2026-07-05, owner)

On the owner's M4 Mac, signed with `ahdishot-dev`:

- ✅ **Settings window** opens from the menu (⌘,) with all current values shown.
- ✅ **Hotkey recorder** records new shortcuts and re-registers live; **bare key ⇒ beep** (reject),
  **Esc** cancels quietly.
- ✅ **Clear / no-hotkey** works — cleared shortcut stops firing globally; menu-bar capture still works;
  setting a new shortcut re-registers.
- ✅ **Save folder** picker, **PNG↔JPG** format, and **default color/thickness** all apply.
- ✅ **Persistence across relaunch** confirmed (settings survive quit/relaunch and rebuilds — UserDefaults
  is keyed to the bundle id).
- ✅ **Launch at Login** toggles the **System Settings ▸ General ▸ Login Items** entry on/off.
- ✅ **Auto-boot after an actual reboot** — app launches automatically on login with all settings intact.
