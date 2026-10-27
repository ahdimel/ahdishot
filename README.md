# ahdishot

A small, native screenshot tool for Apple silicon Macs. Press a hotkey, drag a region, mark it up in
place (boxes, arrows, text, highlighter), then copy or save. It lives in the menu bar and needs no
Rosetta.

Download, install guide, demo and manual: **https://ahdimel.com/ahdishot/**

**Requires:** a Mac with Apple silicon (M1 or later) running macOS 15 Sequoia or later.

## Install from the disk image

1. Download `ahdishot-<version>.dmg` from https://ahdimel.com/ahdishot/, open it, and drag
   **ahdishot** onto **Applications**.
2. Open ahdishot from Applications. macOS says it can't verify the app and won't open it. Click
   **Done**. (ahdishot isn't notarized: that takes a paid Apple developer account.)
3. Go to **System Settings ▸ Privacy & Security**, scroll down to **Security**, and click **Open Anyway**
   next to "ahdishot was blocked". Confirm with **Open Anyway** and your password.
4. A viewfinder icon appears in the menu bar. There's no Dock icon.
5. The first time you capture, macOS asks for screen recording permission. Turn ahdishot on under
   **Privacy & Security ▸ Screen & System Audio Recording**, then quit ahdishot and open it again.

You only do this once. If you'd rather not, build it yourself (below): an app you build locally never
hits the warning.

## Build from source

You need Apple's Command Line Tools with Swift 6 (no Xcode required):

```bash
xcode-select --install          # skip if `swiftc --version` already works
git clone https://github.com/ahdimel/ahdishot.git
cd ahdishot
./build.sh                      # -> build/ahdishot.app
ditto build/ahdishot.app /Applications/ahdishot.app
open /Applications/ahdishot.app
```

`build.sh` signs the app ad hoc. That's fine for one build, but macOS ties the screen recording
permission to the signature, so each rebuild asks for it again. If you rebuild often, create a
self-signed code-signing certificate named `ahdishot-dev` in Keychain Access
(HANDOVER.md §4.1); `build.sh` uses it when it's present.

If the build fails with "this SDK is not supported by the compiler", a leftover SDK from another
Command Line Tools version is being picked up. Point the build at the SDK that matches your
compiler, for example `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ./build.sh`.

`./make-dmg.sh` builds the app and packages it as `build/ahdishot-<version>.dmg`.

## Use

- **⌘⇧2** (or menu bar ▸ Capture Region) dims the screen. Drag a region; drag its handles to adjust.
- The toolbar under the selection has: rectangle, ellipse, arrow, line, pencil, highlighter, text,
  undo, then copy, save and close. Click a tool to choose its color and thickness (or text size).
- **Copy** puts the image on the clipboard. **Save** writes a timestamped PNG to `~/Pictures/ahdishot`.
  **Esc** cancels.
- **Settings…** in the menu changes the hotkey, save folder, PNG or JPG, default color and thickness, and
  launch at login.

## Project docs

- [REQUIREMENTS.md](REQUIREMENTS.md): scope and design decisions.
- [HANDOVER.md](HANDOVER.md): build details, architecture and verification history.

## License

MIT. See [LICENSE](LICENSE).
