# Attic

A native macOS (SwiftUI, macOS 14+) file browser that frees up disk space. You can move big files to your own Cloudflare R2 bucket and bring them back with a double-click.

- **Library:** Home dashboard, Recents, Images/Videos/Music/Documents/Archives/Apps, Large Files, Screenshots, Downloaded From (grouped by `kMDItemWhereFroms`).
- **Plain-English search:** e.g. "pdfs from last week over 5 mb". It shows how it read your search as removable chips, and it also searches text inside screenshots (Apple Vision, on device).
- **Free up space:**
  - Clean Up cards.
  - Duplicates (SHA-256; APFS clones count as freeing nothing).
  - Deep Clean (node_modules, Xcode build folders, Python envs, npm/pip/uv caches, app caches, Trash).
  - Memory & Swap: swap files on disk, plus the memory each app uses, with Quit and Force Quit.
- **Cloudflare R2:**
  - Bucket browser with upload, download, 7-day private links and folders.
  - **Offload:** upload the file, check it in R2, remove the local copy, and leave a `name.ext.attic` placeholder. Double-click the placeholder to restore the file.
  - The bucket is created automatically from the Versely backend's keys (`~/Developer/versely/content-creation-backend/.env`). Keys are stored in the Keychain.
  - Other buckets on the account are read-only unless you turn on writes in Settings.
- Menu bar icon with your latest downloads, and Quick Search (⇧⌘Space) from any app.

## Build

`project.yml` signs with a Developer ID certificate (team `ZMNA9Z2VN7`). If you don't have that certificate, set your own `DEVELOPMENT_TEAM` there. You can also build unsigned by adding `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` to the `xcodebuild` line.

```bash
xcodegen generate
xcodebuild -project Attic.xcodeproj -scheme Attic -configuration Release -derivedDataPath build/dd build
ditto build/dd/Build/Products/Release/Attic.app /Applications/Attic.app
```

## Self-test (no UI)

```bash
build/dd/Build/Products/Release/Attic.app/Contents/MacOS/Attic --selftest            # parser, scanner, memory
build/dd/Build/Products/Release/Attic.app/Contents/MacOS/Attic --selftest --r2       # + R2 round trip (multipart, presign, delete)
build/dd/Build/Products/Release/Attic.app/Contents/MacOS/Attic --selftest --r2 --connect --offload   # + Keychain + offload/restore
```

## Logo

`branding/render-logo.swift` draws every icon size, the menu bar template, the lockups and `attic-icon.svg` from one set of shapes:

```bash
swift branding/render-logo.swift .
```
