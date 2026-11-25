<p align="center">
  <img src="docs/images/banner.png" alt="Attic: free up your Mac, keep everything" width="100%">
</p>

<p align="center">
  <a href="https://github.com/piyushgit011/attic-mac/releases/latest"><img alt="Download" src="https://img.shields.io/github/v/release/piyushgit011/attic-mac?label=download&color=ff7e45&style=for-the-badge"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?style=for-the-badge&logo=apple">
  <img alt="Native SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-F05138?style=for-the-badge&logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/github/license/piyushgit011/attic-mac?color=ee4472&style=for-the-badge"></a>
  <a href="https://github.com/piyushgit011/attic-mac/actions/workflows/build.yml"><img alt="Build" src="https://img.shields.io/github/actions/workflow/status/piyushgit011/attic-mac/build.yml?branch=main&style=for-the-badge&label=build"></a>
</p>

<p align="center">
  <a href="https://piyushgit011.github.io/attic-mac/"><b>Website</b></a> ·
  <a href="https://github.com/piyushgit011/attic-mac/releases/latest/download/Attic.dmg"><b>Download</b></a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

<p align="center">
  <b>Attic is a free, open-source Mac app for when your disk is almost full.</b><br>
  It shows you what's taking the space, finds what you can safely clear,<br>
  and moves big files you want to keep to <b>Cloudflare R2</b> or <b>iCloud Drive</b>, leaving a placeholder you can double-click to bring them back.
</p>

<p align="center">
  <a href="https://github.com/piyushgit011/attic-mac/releases/latest/download/attic-launch.mp4">
    <img src="docs/images/video-poster.jpg" alt="Watch the 54-second launch video" width="85%">
  </a>
  <br><sub>▶ Watch the 54-second launch video</sub>
</p>

---

## Download

Grab **Attic.dmg** from the [latest release](https://github.com/piyushgit011/attic-mac/releases/latest), open it, and drag Attic to Applications. It's signed with a Developer ID and notarized by Apple. You need macOS 14 Sonoma or later, on Apple silicon or Intel.

The first time you open it, macOS asks to let Attic see your Desktop, Documents and Downloads. That's what lets it list your files and work out what's using space.

## What it does

### 🔎 Search the way you talk

Type "pdfs from last week over 5 mb" or "screenshots with wifi password". Attic shows how it read your search as chips you can remove one by one. It also reads the text inside your screenshots on your Mac (Apple Vision), so you can find that Wi‑Fi password, tracking number or receipt by what it says.

<p align="center"><img src="docs/gifs/search.gif" alt="Plain-English search finding a screenshot by the text inside it" width="90%"></p>

### ✨ Clean Up, Duplicates and Deep Clean

- **Clean Up cards** point at forgotten downloads, old installers, old screenshots, big old videos, large files, apps you haven't opened in months, and files that are already safe in iCloud. Every card opens a review page first.
- **Duplicates** finds identical files by their contents (SHA‑256). It knows when two copies are APFS clones that share disk space, so the space it promises is the space you get back.
- **Deep Clean** finds rebuildable bulk: `node_modules`, Xcode build folders, Python environments, `.next` caches, npm/pip/uv/Homebrew caches, app caches, and what's sitting in the Trash.

<p align="center"><img src="docs/gifs/cleanup.gif" alt="Clean Up, Duplicates and Deep Clean" width="90%"></p>

<table>
  <tr>
    <td><img src="docs/images/duplicates.jpg" alt="Duplicates"></td>
    <td><img src="docs/images/deep-clean.jpg" alt="Deep Clean"></td>
  </tr>
</table>

### 🧠 Memory & Swap

When memory runs short, macOS writes it to swap files on your disk, and those can quietly take 10 GB or more. Attic shows how much swap is in use, how many swap files are on disk, and which apps are holding the most memory, with **Quit** and **Force Quit** buttons right there.

<p align="center"><img src="docs/images/memory.jpg" alt="Memory and swap" width="90%"></p>

### ☁️ Offload to Cloudflare R2 or iCloud Drive

Pick big files and choose where they go:

| | Cloudflare R2 | iCloud Drive |
|---|---|---|
| Where the file goes | A private bucket of your own | iCloud Drive ▸ Attic |
| What stays on your Mac | A tiny `name.ext.attic` placeholder | A link in the original folder |
| How you get it back | Double-click the placeholder, or **Restore** | Open it (it downloads), or **Restore** |
| Safety check | Content-MD5 on every part, then size check in R2 before anything is removed | Removed from this Mac only after iCloud reports the upload finished |
| Cost | About $0.015 per GB a month, no download fees | Counts toward your iCloud plan |

Files already in iCloud (Desktop & Documents) just get **Remove Download**: they stay in place and download again when you open them.

<p align="center"><img src="docs/gifs/offload.gif" alt="Offloading two videos to Cloudflare R2" width="90%"></p>

<table>
  <tr>
    <td><img src="docs/images/offload-r2.jpg" alt="Offload to R2"></td>
    <td><img src="docs/images/offload-icloud.jpg" alt="Offload to iCloud Drive"></td>
  </tr>
  <tr>
    <td><img src="docs/images/cloud.jpg" alt="R2 bucket browser"></td>
    <td><img src="docs/images/offloaded.jpg" alt="Offloaded files"></td>
  </tr>
</table>

The R2 browser also works on its own, like a Finder window for your bucket: upload by drag and drop, download, make folders, and copy private links that expire after 7 days.

### ✺ AI that stays on your Mac

Attic uses the intelligence that already ships with macOS, and nothing is ever sent anywhere:

- **Apple Intelligence (on-device model).** When a search has words Attic's rules can't place, like "the invoice my accountant emailed me", Apple's local model turns it into filters (Documents · From Gmail · "invoice"). The chips show **Apple Intelligence · on this Mac** when it helped. This needs macOS 26 with Apple Intelligence on; without it, search still works.
- **Apple Vision (the Live Text engine)** reads the text in your screenshots and recent images, so you can search it, see it in the inspector, and copy it with **⇧⌘C** or the Copy Text button.
- **Siri & Shortcuts:** "Find files in Attic", "How much space is left in Attic", "Free up space with Attic".

<p align="center"><img src="docs/images/ai-search.jpg" alt="Apple Intelligence search on this Mac" width="90%"></p>

### ⌘ Quick Search, from any app

Press **⇧⌘Space** anywhere for a small search panel that understands the same plain English. Press **↩** to open, **⌥↩** to show in Finder, or **⌘↩** to show in Attic. Attic's menu bar icon also lists your last ten downloads, ready to drag into Mail or Slack.

<p align="center"><img src="docs/gifs/quicksearch.gif" alt="Quick Search" width="80%"></p>

### 📥 Downloaded From, and everything else

Every download is grouped by where it came from: Gmail, Google Drive, ChatGPT, Slack, GitHub, or any website. The app also has grid and list views with sorting everywhere, Back and Forward (⌘[ / ⌘]), Quick Look with Space, an inspector, and a library of images, videos, music, documents, archives and apps.

<table>
  <tr>
    <td><img src="docs/images/downloaded-from.jpg" alt="Downloaded From"></td>
    <td><img src="docs/images/large-files.jpg" alt="Large files"></td>
  </tr>
</table>

## Setting up Cloudflare R2

Open **Cloud** in the sidebar and use one of these:

- **Use an existing backend's keys.** Point Attic at a `.env` file that has `CF_ACCOUNT_ID`, `CF_R2_ACCESS_KEY_ID` and `CF_R2_SECRET_ACCESS_KEY`. Attic creates a bucket just for this Mac (for example `attic-macbook-pro`) and saves the keys in your Keychain.
- **Enter keys yourself:** account ID, access key, secret and bucket name.

Other buckets on the same account are **read-only** in Attic unless you turn on changes in Settings, so a shared production bucket can't be modified by accident.

## Privacy and safety

- Your files are never uploaded unless **you** offload them. Text recognition (Apple Vision), search help (Apple Intelligence's on-device model) and duplicate detection all run on your Mac.
- Nothing is deleted outright. Clean Up, Duplicates and Deep Clean move things to the Trash, and offloading removes a local copy only after the upload checks out.
- iCloud-only files aren't using space on your Mac, so Attic labels them and doesn't count them toward what you can free.
- No account and no analytics. The only network traffic goes to the R2 bucket you set up.

## Open source

Attic is MIT licensed and has no server, account or tracking. Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md), and report security issues privately as described in [SECURITY.md](SECURITY.md). Every push is built and self-tested on a GitHub Mac runner.

## Build from source

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Attic.xcodeproj -scheme Attic -configuration Release -derivedDataPath build/dd build
open build/dd/Build/Products/Release/Attic.app
```

`project.yml` signs with a Developer ID certificate (team `ZMNA9Z2VN7`). To build without it, add `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` to the `xcodebuild` line.

### Self-tests

```bash
APP=build/dd/Build/Products/Release/Attic.app/Contents/MacOS/Attic
$APP --selftest                                  # search parser, on-device AI, scanner, memory & swap
$APP --selftest --r2                             # R2: multipart upload, download check, private link, delete
$APP --selftest --r2 --connect --offload         # + Keychain + offload to R2 and restore from a placeholder
$APP --selftest --icloud                         # offload to iCloud Drive, wait for upload, free, restore
```

### Demo mode, screenshots and the launch video

Every image and GIF in this README comes from a made-up sample library, not anyone's real files.

```bash
swift branding/demo/make-demo.swift "$HOME/Attic Demo" && branding/demo/make-media.sh "$HOME/Attic Demo"
branding/demo/run-tour.sh stills build/shots           # screenshots of every screen
branding/demo/run-tour.sh search build/rec/search.mov  # scripted recordings (search, cleanup, memory, offload, quicksearch…)
swift branding/make-readme-art.swift .                 # README artwork
cd launch-video && npm install && npm run render       # the launch video (Remotion)
```

## Project layout

```
Sources/
  App/        app entry, navigation, Siri & Shortcuts, self-tests, demo mode & tours
  Model/      file items, categories, formatting
  Services/   scanner, search parser, on-device AI (Apple Intelligence), Clean Up, Duplicates, Deep Clean, OCR, memory & swap
  Cloud/      R2 client (AWS Signature V4, multipart, presigned links), offload/restore, iCloud Drive
  Views/      SwiftUI screens
branding/     logo renderer, README art, demo library and recording tools
launch-video/ Remotion project for the launch video
docs/         website (GitHub Pages) and README images
```

## License

MIT. See [LICENSE](LICENSE).
