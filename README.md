# Iris by AriZe

A personal AI assistant for your computer: conversation, voice, knowledge, screen guidance, drafting, creation and background agents.

- **macOS 2.0.32**: the primary, actively developed app. Open `macOS/Project IRIS.xcodeproj` in Xcode 27.2 or later; Apple Silicon, macOS 15+.
- **iPhone 1.1 preview**: a separate iOS 18+ companion. See [its guide](iOS/README.md).
- **Windows 1.0**: a frozen, unsigned test edition, with feature differences and no claim of full Mac parity. See [its guide](windows/README.md).
- **Website**: maintained separately at [Project-Iris-Website](https://github.com/MustafaS22/Project-Iris-Website).

[Download Iris](https://projectiris.lovelyabbey.chatgpt.site/download) · [Release notes](https://projectiris.lovelyabbey.chatgpt.site/releases)

## Screenshots

### Desktop chat

![Desktop chat](docs/screenshots/assistant.jpg)

### Notch chat

![Notch chat](docs/screenshots/notch.jpg)

### Knowledge library

![Knowledge library](docs/screenshots/knowledge.jpg)

## Build and test

Choose your own Apple signing team in Xcode. Sparkle 2.10.1 resolves through Swift Package Manager. Run core checks with `swift test --package-path macOS/IrisCoreTests` and `swift test --package-path iOS/Tests`; Windows unit checks use `npm ci` then `npm test` in `windows/`.

Google sign-in needs your own OAuth registration. Copy `macOS/Configuration/GoogleOAuth.example.json` to `macOS/Project IRIS/GoogleOAuth.json` and configure your registered desktop client. The real OAuth configuration, API keys, user memory/knowledge, signing private keys, profiles, local build outputs and downloaded reference projects are intentionally excluded.

## Release updates

Public source is synchronized at release time. The maintainers use `tools/sync-source.py` with a local path configuration; see `tools/sync-config.example.json`. `SOURCE_MANIFEST.json` records the exact public source snapshot. Signing keys stay in macOS Keychain. Source synchronization never changes the working app or user data.

## Credits and licensing

Developed by **AriZe**. Existing third-party attribution and asset licenses remain with their corresponding files. No additional blanket open-source license is granted by this repository.
