# Security

## Reporting a vulnerability

Please report security issues privately through **GitHub ▸ Security ▸ [Report a vulnerability](https://github.com/piyushgit011/attic-mac/security/advisories/new)** rather than in a public issue. You'll get a reply within a few days.

## How Attic handles your data

- **Credentials.** Cloudflare R2 keys are stored in your macOS Keychain, never in plain files. Buckets other than the one Attic created are read-only unless you turn on writes in Settings.
- **Uploads.** Nothing leaves your Mac unless you offload it. Uploads go straight to your own R2 bucket or iCloud Drive; there is no Attic server.
- **AI.** Text recognition (Apple Vision) and search help (Apple Intelligence's on-device model) run locally. No prompts, files or text are sent anywhere.
- **Deletion.** Clean Up, Duplicates and Deep Clean move items to the Trash. Offloading removes a local copy only after the cloud copy checks out (MD5 per part and a size check for R2; iCloud's own upload status for iCloud Drive).
- **Telemetry.** None.
