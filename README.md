# Screen Room Remote

A local macOS prototype for controlling a compatible Fire OS device, looking up films and chatting about movies. Built with SwiftUI, App Intents and Apple Foundation Models.

## What works

- Home, Back, directional, Select and Play/Pause remote commands over a paired ADB connection.
- Netflix and YouTube app launch, a user-selected YouTube video link, and a TV screenshot when the current app permits capture. The YouTube deep link is experimental and requires a compatible Fire TV YouTube app.
- Film search using the bundled Screen Room catalog. Add your own TMDB API key or v4 read token in the search sheet to use the live catalog; the app stores it in macOS Keychain. The film query is sent to TMDB. Without a key, three sample films are available.
- Text chat using Apple Foundation Models on a supported Mac with Apple Intelligence enabled. A movie-search tool may send a query to TMDB; it reports when that tool returns results. Model answers can be inaccurate.
- A read-only TV connection App Shortcut. Siri discovery and presentation have not yet been verified.

Catalog results do not establish streaming availability. Netflix may block screenshots. Opening Netflix does not automatically select a film. Voice chat, Focus, YouTube browsing-history import and cross-device iOS handoff are not implemented.

## Run from source

Requires macOS 27, Xcode 27, XcodeGen and Android SDK Platform Tools (`adb`) installed in `/opt/homebrew/bin` or `/usr/local/bin`. The TV must support network ADB, be on the same network, and be paired with the owner's consent. Enable ADB debugging on the TV, enter its IP in the app and select Connect, then accept the prompt on the TV. Turn debugging off when finished.

Run `./script/build_and_run.sh`. The script creates a local, unsigned debug app; it is not a signed or notarized release. Do not expose ADB to the public internet. Older Fire OS devices and newer non-Android Fire TV devices can differ.

The catalog uses TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB. The local ScreenRoomKit source is included under this repository's license. See LICENSE.
