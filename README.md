# Shuno

A modern, **100% ad-free**, local-first audio player built with Flutter, designed specifically for an immersive **Audiobook + PDF Reading** experience, podcast listening, and long-form spoken-word audio.

---

## Highlights

### 📖 Immersive Audiobook + PDF Reader
- **Simultaneous Read & Listen**: Read the original book or document while listening to the narration.
- **Distraction-Free Immersion**: Audio controls and top app bars dim and fade smoothly while reading, giving you maximum screen space for reading.
- **Smart Sibling Matching**: Automatically detects multi-part audiobook tracks and associates them with the same book PDF across your library.
- **Dual Bookmarking**: Automatically persists your exact reading page and audio playback position across sessions.
- **Fluid PDF Navigation**: Fast page-jumping slider, grid preview, and title management.

### 🚫 100% Ad-Free & Distraction-Free
- Zero advertisements, zero interruptions, and zero commercial banners.
- No accounts, logins, subscriptions, or tracking. Your listening habits stay private on your device.

### 🎧 Audio & Spoken-Word Playback
- **Gesture-Driven Track Navigation**: Swipe left or right on either the mini-player or the full player card to skip tracks, accompanied by interactive real-time title translations.
- **Dynamic Title Marquee**: Long titles smoothly scroll with marquee animations across both the playback bar and full-screen player sheet.
- **Fine-Grained Speed Control**: Adjust playback speed from `0.75x` up to `2.5x` with pitch preservation.
- **Quick Scrubbing**: Double-tap the player or reader to skip 10 seconds backward or forward with visual feedback.
- **Custom Sleep Timer**: Set a countdown timer (`15m`, `30m`, `45m`, `60m`) or stop playback automatically at the **End of Track**.
- **Background & Screen-Off Playback**: Native foreground audio service (`audio_service`) with persistent system notifications and lock-screen controls.

### 💾 Offline Listening & Local-First Storage
- **Download for Offline Listening**: Save audio tracks directly to device storage for 100% offline access when traveling.
- **Resume Where You Left Off**: Automatically remembers your last playback position for offline audio tracks.
- **Local JSON Persistence**: Lightweight, battery-efficient local storage without heavy databases or external services.

### 🗂️ Library & Queue Management
- **Spotify-Grade Multi-Tier Queue**: Prioritizes manual user additions (`Play Next`, `Add to Queue`) above playlist context and transient autoplay recommendations. Manually queued tracks persist across new track searches, while stale autoplay recommendations are automatically purged upon starting a new track.
- **Granular Queue Controls**: Independent "Clear queue" action for user-queued tracks, visual "In Queue" badges, and reorderable drag-and-drop handles.
- **Custom Playlists & Channels**: Group chapters and series into custom playlists, or explore channels and catalog playlists directly.
- **Favorites & History**: Quick-access bookmarks and timestamped listening history.
- **Theming**: Premium dark design with high-contrast playback controls and interchangeable color palettes (*Emerald*, *Cyan*, *Amethyst*, *Amber*).

---

## Architecture Overview

Built following clean architecture principles (**KISS**, **DRY**, **YAGNI**):
- **Zero bloat**: Uses native Flutter state management (`ChangeNotifier` / `ValueNotifier`) without heavy third-party framework overhead.
- **Efficient UI rendering**: Scoped rebuilds and isolated stream notifiers ensure smooth scrolling and low battery consumption.
- **Offline-first**: All preferences, bookmarks, playlists, and downloads reside locally on-device.

```text
lib/
  main.dart                           # App lifecycle, background audio setup, theme builder
  models/
    download_item.dart                # Offline audio metadata & position tracking
    playlist.dart                     # Custom playlist model
    youtube_channel_item.dart         # Channel metadata model
    youtube_playlist_item.dart        # Playlist collection model
    youtube_search_item.dart          # Audio track model & metadata serialization
  services/
    audio_handler.dart                # Background audio service & lock-screen media controls
    book_service.dart                 # PDF validation, title sanitization, and query matching
    download_service.dart             # Local audio downloader and progress manager
    playback_controller.dart          # Multi-tier playback queue, loop/shuffle, and speed controls
    storage_service.dart              # Local JSON persistence with debounced writes
    youtube_service.dart              # Audio resolution, search, channel & playlist discovery
  screens/
    audiobook_reader_screen.dart      # Immersive PDF reader with audio playback dock
    channel_detail_screen.dart        # Channel exploration, uploads, and channel playlists
    home_navigation_screen.dart       # Bottom navigation container with docked mini-player
    library_screen.dart               # Tabbed library (Playlists, Favorites, History, Downloads)
    playlist_detail_screen.dart       # Playlist track list, reordering, and batch management
    queue_screen.dart                 # Multi-tier active playback queue with user-queue controls
    search_screen.dart                # Compact audio discovery & catalog exploration
    settings_screen.dart              # Audio quality, themes, and storage management
    youtube_playlist_detail_screen.dart # Catalog playlist track list and playback
  widgets/
    animated_equalizer.dart           # Real-time animated playback indicator
    attach_pdf_sheet.dart             # PDF selector and local file attachment modal
    full_player_sheet.dart            # Expandable full now-playing sheet with swipe gesture & isolated scrubber
    marquee_text.dart                 # Smooth auto-scrolling marquee text for long titles
    playback_bar.dart                 # Persistent bottom mini-player with swipe gestures & progress bar
    track_tile.dart                   # Modular track tile with PDF indicators and quick actions
```

---

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.19.0 or higher)
- Android SDK with API Level 21+

### Build & Run

```bash
# Clone the repository
git clone https://github.com/your-username/shuno.git
cd shuno

# Install dependencies
flutter pub get

# Run on a connected device
flutter run

# Run automated tests
flutter test

# Build release APK
flutter build apk --release
```

---

## Disclaimer & Legal Notice

> [!IMPORTANT]
> This software is provided strictly for **educational, personal, and research purposes**.

- **No Media Hosting**: This repository does not host, store, or distribute any copyrighted media, audio files, or book documents. All media streams, metadata, and files accessed or played through this application originate from third-party endpoints or files supplied locally by the end-user.
- **Third-Party Terms & Compliance**: The authors and contributors of this project do not endorse, encourage, or facilitate the unauthorized downloading, distribution, or circumvention of terms of any third-party content providers. Users are solely responsible for ensuring that their use of this software complies with all applicable local, national, and international laws, regulations, and third-party Terms of Service.
- **Limitation of Liability**: Under no circumstances shall the authors, maintainers, or copyright holders of this repository be held liable for any claim, damages, legal actions, copyright infringements, or other liabilities arising from the use, misuse, modification, or redistribution of this software or its source code by third parties.

---

## License

This project is licensed under the terms of the [MIT License](LICENSE).
