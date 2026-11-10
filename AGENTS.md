# Screen Room Remote: Repository Guidelines

Screen Room Remote is a local, unsigned macOS 27 prototype that controls a paired Fire OS TV over network ADB, looks up films and chats about them with on-device Foundation Models. Bundle `com.screenroom.remote`, product name "Screen Room Remote". This repository is **public**: never commit private paths, account IDs, TMDB keys, TV IP addresses, screenshots of a real TV session or personal data.

## Structure

- `project.yml` (XcodeGen) is the source of truth. `*.xcodeproj/` is git-ignored: run `xcodegen generate` before `xcodebuild` and after adding, moving or deleting a file.
- `Sources/ScreenRoomRemote` is the whole app (one target, `SWIFT_VERSION 5.0`, `CODE_SIGNING_ALLOWED: NO`). There is no test target.
- `Vendor/ScreenRoomKit` is a trimmed copy of the ScreenRoomKit package from the private Screen Room app, kept under this repository's licence. Edit it here; it does not track the original.
- `ModelRelay` comes from `https://github.com/Juanpe/ModelRelay.git`, `exactVersion: 0.2.0`. No `Package.resolved` is committed, so its own dependencies (including AnyLanguageModel, which has a build-time macro) resolve fresh on each clean build.

## Build and run

- `./script/build_and_run.sh` runs `xcodegen generate`, then `xcodebuild -skipMacroValidation -project ScreenRoomRemote.xcodeproj -scheme ScreenRoomRemote -configuration Debug -derivedDataPath "$PWD/build" CODE_SIGNING_ALLOWED=NO build`, copies the app to `dist/` and opens it. Passing is `** BUILD SUCCEEDED **`. (unverified on 10 Nov 2026: package resolution needs GitHub)
- To build without launching, run the same `xcodegen generate` and `xcodebuild` lines yourself; the script's `open -n` starts the app.
- `-skipMacroValidation` is required for the AnyLanguageModel macro; keep it.
- The app calls `adb` at `/opt/homebrew/bin/adb`, else `/usr/local/bin/adb`. Connecting to a TV, sending keys or capturing its screen drives the owner's real TV: do it only when the owner asks, and never expose ADB beyond the local network.

## Product rules

- A sent remote command does not prove playback or volume changed; Now Playing reads the TV's media session and never infers titles from images. Keep the UI saying which source answered.
- A TMDB key the person enters is stored in the macOS Keychain; without one the app uses three sample films.
- "Send to Folio" writes a screenshot and sidecar into `Folio/Inbox` in the App Group `group.com.anupamchugh.alcor`, or `AlcorGroupFallback` in the temporary folder when the group container is unavailable (the app has no entitlements file).

## Tasks

- No beads ledger in this repository (10 Nov 2026); `bd where` from a worktree falls through to an unrelated home-folder ledger, so do not file work there. Take the task the owner names.

## Commit

- Subjects are short imperative sentences (`Add TV state and on-device movie tools`); some use `feat(remote): ...`. End with a `Co-Authored-By:` trailer.

## Releases

- None: no signing, notarization, fastlane or release lane exists, and the README says the app is not a signed or notarized release. Signing, notarizing or publishing a build needs the owner's approval for that exact action.
