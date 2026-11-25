# Changelog

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
