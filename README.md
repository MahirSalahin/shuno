# Shuno

A small personal-only YouTube audio client for Android built with Flutter.

Shuno provides a clean music-style experience: search YouTube, maintain an active queue, create local playlists, manage favorites and history, download songs for offline playback, and continue listening in the background with lock-screen and notification controls when the screen is turned off.

## Features

- **Audio Playback**: Streaming playback powered by `just_audio` with scrubber, buffer progress, and quality selection.
- **Background & Screen-Off Playback**: Android foreground media service (`audio_service` / `just_audio_background`) with wake-lock support.
- **Notification & Lock-Screen Controls**: System media notification with artwork, track title, channel, play/pause, next/previous, and seek bar.
- **Queue Management**: Active queue with now-playing indicator, drag-to-reorder, swipe-to-delete, play next, and clear queue.
- **Autoplay**: When the queue finishes, automatically resolves and queues related YouTube tracks to keep playback going.
- **Next / Previous**: Skip controls on the mini player, full-screen player, and system notification.
- **Local Playlists**: Create custom playlists, add/remove tracks, rename, and play whole playlists with one tap.
- **Favorites**: One-tap heart toggle on any track, with a dedicated Favorites tab in Library.
- **Play History**: Automatic timestamped log of recently played tracks with replay and clear history options.
- **Downloads & Offline Playback**: Save audio streams directly to local storage (`downloads/<id>.m4a`) and listen 100% offline without internet.
- **Local Persistence**: Zero-database JSON storage (`shuno_data.json`) via `path_provider` (pure Dart, fast, no `build_runner` or ORM bloat).
- **Settings**: Toggle autoplay, choose preferred audio quality (High vs Data Saver), and manage storage / clear cache.
- **Polished Material 3 UI**: Dark theme with mint/teal accents, persistent mini player, expandable full-screen now-playing sheet, and intuitive bottom navigation.

## Architecture

Built adhering strictly to **KISS**, **DRY**, and **YAGNI**:
- No external state-management frameworks (uses native `ChangeNotifier`).
- No heavy databases or code generation (clean JSON persistence).
- No backend servers or user accounts (personal, local-first client).

```text
lib/
  main.dart                           # App entry, JustAudioBackground setup, Theme
  models/
    youtube_search_item.dart          # Track model with JSON serialization and formatting
    playlist.dart                     # User playlist model
    download_item.dart                # Downloaded track metadata and file size
  services/
    youtube_service.dart              # Search, audio stream resolution, and related videos
    playback_controller.dart          # Queue, player state, loop modes, shuffle, background sync
    storage_service.dart              # JSON persistence for favorites, history, playlists, downloads, settings
    download_service.dart             # Chunked stream downloading to disk with progress tracking
  screens/
    home_navigation_screen.dart       # Scaffold with NavigationBar and docked PlaybackBar
    search_screen.dart                # YouTube search with quick chips and Action menus
    library_screen.dart               # Tabbed library (Playlists, Favorites, History, Downloads)
    playlist_detail_screen.dart       # Playlist tracks view, play all, edit/delete
    queue_screen.dart                 # Reorderable upcoming queue, clear queue
    settings_screen.dart              # Preferences and storage management
  widgets/
    playback_bar.dart                 # Persistent mini player with progress indicator
    full_player_sheet.dart            # Expandable full now-playing sheet with scrub bar
    track_tile.dart                   # Reusable track tile with popups (Play, Queue, Playlist, Favorite, Download)
    add_to_playlist_dialog.dart       # Dialog to add songs to existing or new playlists
```

## Running on Android

From PowerShell:

```powershell
Set-Location F:\Programs\Flutter\shuno
flutter pub get
flutter devices
flutter run -d <android-device-id>
```

## Verification

```powershell
flutter analyze
flutter test
flutter build apk --debug
```
