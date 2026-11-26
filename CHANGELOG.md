# Changelog

## 1.3.1
- **Large Files leaves out app libraries.** Photos, Music, TV, iMovie, Final Cut and Lightroom libraries are no longer listed or counted in the red badge, since trashing or moving one can damage it. A note at the top shows how big they are and how to free space from inside their app (for Photos, iCloud Photos with Optimize Mac Storage).
- When nothing big takes space on your Mac, Large Files says so and counts the big files that are only in iCloud.
- App libraries show their Finder names: "Photos Library", not "Photos Library.photoslibrary".

## 1.3.0
- **A Finder alternative.** Locations in the sidebar (home, Desktop, Documents, Downloads, Pictures, Movies, Music, Developer, iCloud Drive, Applications) open like Finder: folders as cards with their files peeking out, big thumbnails, a clickable path bar, folder sizes measured in the background, and live updates when something changes.
- **Finder actions:** drag files onto any folder to move them (⌥ copies), New Folder (⇧⌘N), Rename, Go to Folder (⇧⌘G), Enclosing Folder (⌘↑), Show Hidden Files (⇧⌘.), Show in Enclosing Folder, and pinned folders in the sidebar.
- **New look.** Home shows your Library as soft coloured folders, Clean Up cards, your folders, recent screenshots and where downloads came from. A new search bar sits on the left of the top bar (⌘F) with free space beside it, and every list has From, Kind, Date, Size and Sort filters.
- **Two looks: Playful and Minimal** (⌃⌘T), plus a Light / Dark / Same as my Mac setting.
- **Screenshot history.** If your Mac copies screenshots to the clipboard, Attic can save each new one to Pictures ▸ Screenshots so you can find it and search its text. Only real screenshots are kept.
- **Duplicates** are found in the background and shown with Keep and Trash tags; "Keep 1, Trash the rest" per group.
- **Saved searches** in the sidebar, a **music player** in the top bar, and an inspector with dimensions, duration, camera and folder sizes for any file, indexed or not.
- **Get Latest Download** for Shortcuts and Siri. Open Attic at login.
- **Safety:** app libraries (Photos, Music, TV, iMovie, Final Cut, Lightroom) are never offloaded or evicted, and an older offload of one is never evicted. Restoring from iCloud Drive falls back to a plain move for packages.
- New app icon.

## 1.2.2
- **Deep Clean judges activity correctly.** It used git's index file, which editors rewrite constantly, so every project looked "used today". It now goes by your last commit or checkout and dependency changes.
- Build caches (`.next`, Xcode `build/`, Swift `.build`) are always offered, and dependencies once a project has been idle a week.
- Folders a running app or dev server is using are marked **In use right now** and never selected.

## 1.2.1
- Full Disk Access is now detected correctly on recent macOS, so app data like WhatsApp media and Mail is measured once you turn it on.

## 1.2.0
- **Storage breakdown.** A new Storage screen splits the disk into buckets you can act on: your files, Projects (~/Developer), app data, other home folders, caches & temporary files, developer tools, simulators, Trash, swap and macOS, with the biggest folders in each. Home's storage bar now shows these buckets instead of one grey "System & other".
- **Leftover app copies.** Deep Clean finds the copies some apps (like Chrome) make of themselves at every launch and never remove, and estimates their real size correctly (copies share disk blocks).
- Tells you when Full Disk Access is needed to measure app data such as WhatsApp media, and opens the right setting.

## 1.1.0
- **On-device AI search.** When a search has words Attic's rules can't place ("the invoice my accountant emailed me"), Apple Intelligence's on-device model turns it into filters. Nothing leaves your Mac.
- **Siri & Shortcuts:** "Find files in Attic", "How much space is left in Attic", "Free up space with Attic".
- **iCloud Drive offload:** Remove Download for files already in iCloud; other files move to iCloud Drive ▸ Attic with a link left behind.
- Text search ignores punctuation ("wifi" finds "Wi‑Fi"), and the Clean Up total counts each file once.
- iCloud-only files count as 0 bytes on this Mac, and you can delete them from iCloud when macOS won't trash them.
- Website, contributing guide, CI build.

## 1.0.0
- First release: plain-English search with text inside screenshots, Clean Up cards, Duplicates, Deep Clean, Memory & Swap, Cloudflare R2 offload with placeholders, bucket browser, Quick Search (⇧⌘Space), menu bar downloads.
