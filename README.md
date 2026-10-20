# DeezDown

An unofficial macOS app and command line tool for downloading music from Deezer.

## Install

Requires macOS 26 or later.

Download the latest zip from [Releases](https://github.com/KnlnKS/deezdown/releases/latest), unzip, drag `DeezDown.app` into Applications. Then clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/DeezDown.app
```

The command line tool is the `deezdown-*.tar.gz` on the same release:

```sh
tar -xzf deezdown-*.tar.gz
xattr -d com.apple.quarantine deezdown
sudo mv deezdown /usr/local/bin/
```

Builds are not signed with an Apple Developer ID, so macOS blocks them until you clear the flag.

## Use

Sign in on Deezer's own page from the app, or with `deezdown login`. Only the session cookie is kept, in the Keychain.

```sh
deezdown https://www.deezer.com/album/302127
deezdown search daft punk
deezdown config get
```

Albums, playlists, artists and tracks download in FLAC, MP3 or 360 Reality Audio, tagged with their cover art and, if you want, lyrics.

## Build it yourself

```sh
brew install xcodegen
swift test
xcodegen generate --spec App/project.yml
open App/DeezDown.xcodeproj
```

`DeezDownKit` is the Deezer Swift library; the app and the `deezdown` CLI sit on top of it.

## License

[MIT](LICENSE).

## Not affiliated with Deezer

DeezDown is unofficial. It is not affiliated with, endorsed by, or connected to Deezer, and Deezer is their trademark. Use it at your own risk and stay within Deezer's terms of service.
