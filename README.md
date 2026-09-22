# Shuno

A personal Android Flutter experiment. Milestone 1 contains YouTube search only.

## Run on Android

From PowerShell:

```powershell
Set-Location F:\Programs\Flutter\shuno
flutter pub get
flutter devices
flutter run -d <android-device-id>
```

Replace `<android-device-id>` with the ID printed by `flutter devices`. Start an
Android emulator or connect an Android phone with USB debugging enabled first.

## Checks

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

## Manual review

1. Launch: dark Material 3 screen, Shuno title, search field/button, initial hint.
2. Submit empty text or spaces: validation appears without a request.
3. Search `lofi music`: a spinner appears and submission is disabled until done.
4. Check results for thumbnails, titles, channel names, and available durations.
5. Tap a result: a message displays the title and video ID.
6. Submit another query using the keyboard search action: results are replaced.
7. Try an unlikely query such as `zxqv987654321nonexistentabc`: if YouTube returns
   no videos, the no-results message appears. YouTube may still return matches;
   the automated tests cover an empty response deterministically.
8. Disable both Wi-Fi and mobile data, then search: an error appears (timeout is
   20 seconds). Restore connectivity and press Search again to recover.

## Structure

- `lib/main.dart`: app entry and theme.
- `lib/screens/search_screen.dart`: local widget state and search/result UI.
- `lib/services/youtube_service.dart`: direct `youtube_explode_dart` search,
  first page only, with timeout and HTTP client cleanup.
- `lib/models/youtube_search_item.dart`: result fields and duration display.
- `test/search_screen_test.dart`: deterministic search-state checks.

Search uses [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart)
without an API key. Real searches need internet access. Playback and persistence
are not implemented. No state-management or dependency-injection framework is used.

The dependency is pinned to **3.0.5**: live verification exposed a `getT`
`NoSuchMethodError` in 3.1.0's search parser. The service uses `searchContent`
with `TypeFilters.video` to avoid a separate upload-date parsing failure in
`search()` for results labeled "Streamed ...". It maps only the fields needed
by this milestone. Recheck these upstream issues before upgrading the package.
