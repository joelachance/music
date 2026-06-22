# MiniSpotify

A tiny native macOS Spotify controller. The app shows the current album artwork, overlays one play/pause button, and updates the Dock icon to the current artwork.

This controls the installed Spotify desktop app with macOS Apple Events. Spotify must be installed and logged in.

## Commands

```sh
make test
make run
make stop
```

To start a specific Spotify track URI:

```sh
make run-track TRACK_URI=spotify:track:2IClzYyvgwrsmVVipYsx5T
```

To verify Spotify's local automation surface:

```sh
make spotify-check
```

macOS will ask once for permission to let MiniSpotify control Spotify.

MiniSpotify launches Spotify hidden when it needs playback and then returns focus to itself. Running `make run` without a track does not launch Spotify.

GX smoke test 2026-06-22T12:25:23Z
