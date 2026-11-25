# Contributing to Attic

Thanks for helping. Attic is a native SwiftUI app, and contributions of any size are welcome: bug reports, fixes, new Clean Up cards, translations, docs.

## Get it running

```bash
brew install xcodegen
xcodegen generate
open Attic.xcodeproj          # or build from the command line:
xcodebuild -project Attic.xcodeproj -scheme Attic -configuration Debug -derivedDataPath build/dd \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

`project.yml` is the source of truth for the Xcode project. Edit it rather than the `.xcodeproj`, then run `xcodegen generate`.

## Before you open a pull request

1. **Run the self-tests.** They exercise the engine without the UI:
   ```bash
   build/dd/Build/Products/Debug/Attic.app/Contents/MacOS/Attic --selftest
   ```
   Add `--r2` and `--icloud` if you touched cloud code (those need your own R2 bucket or iCloud Drive).
2. **Check it in demo mode** if you changed anything visible. That way no real files show up in screenshots:
   ```bash
   swift branding/demo/make-demo.swift "$HOME/Attic Demo" && branding/demo/make-media.sh "$HOME/Attic Demo"
   open build/dd/Build/Products/Debug/Attic.app --args -AtticDemo "$HOME/Attic Demo"
   ```
3. **Keep the safety rules.** Attic never deletes outright (everything goes to the Trash). It only removes a local copy after the cloud copy checks out, and it never uploads anything the user didn't choose to offload. The AI features must stay on-device.

## Where things live

| Folder | What's there |
|---|---|
| `Sources/Services` | Scanner, search parser, on-device AI, Clean Up, Duplicates, Deep Clean, OCR, memory & swap |
| `Sources/Cloud` | R2 client (Signature V4, multipart, presigned links), offload/restore, iCloud Drive |
| `Sources/Views` | SwiftUI screens |
| `Sources/App` | App entry, navigation, Siri & Shortcuts, self-tests, demo mode & tours |
| `branding/` | Logo renderer, README art, demo library and recording tools, release script |
| `launch-video/` | Remotion project for the launch video |
| `docs/` | Website (GitHub Pages) and README images |

## Style

Plain Swift, no third-party dependencies. Keep user-facing text short and specific ("Moved 3 files (1.2 GB) to the Trash", not "Operation completed successfully").

By contributing you agree your work is released under the [MIT license](LICENSE).
