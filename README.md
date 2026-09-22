# Shuno

A personal Android Flutter experiment. Milestone 1 added YouTube search;
Milestone 2 adds single-video foreground audio with play/pause and retry.

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

Optional live Android playback check (requires internet and may play audio):

```powershell
flutter test integration_test/playback_smoke_test.dart -d <android-device-id>
```

This checks a real YouTube result, native playback position advancing, and pause.

Milestone 2 verification: static analysis and all 19 unit/widget tests passed.
The live playback check passed on the Android 14 x64 emulator using
`jNQXAC9IVRw`. Playback of every search result is not guaranteed; see the
HTTP 403 limitation below.

`android/gradle.properties` disables Kotlin incremental compilation because
plugin compilation failed with "different roots" when this workspace was on
`F:` and the Pub cache on `C:`. Kotlin rebuilds may take longer; Dart hot reload
is unaffected. See the [Kotlin cache documentation](https://kotlinlang.org/docs/gradle-compilation-and-caches.html).

## Manual review

1. Launch: dark Material 3 screen, Shuno title, search field/button, initial hint.
2. Submit empty text or spaces: validation appears without a request.
3. Search `lofi music`: a spinner appears and submission is disabled until done.
4. Check results for thumbnails, titles, channel names, and available durations.
5. Tap a regular video: the bottom bar shows its title/channel and loading status,
   then audio starts. Tap Pause and Play to verify both controls.
6. Tap a different result: the old audio stops and the new video loads. Additional
   result taps are disabled while audio is loading to prevent overlapping requests.
7. Submit another query using the keyboard search action: results are replaced
   while the current audio and controls remain available.
8. Try an unlikely query such as `zxqv987654321nonexistentabc`: if YouTube returns
   no videos, the no-results message appears. YouTube may still return matches;
   the automated tests cover an empty response deterministically.
9. Disable both Wi-Fi and mobile data, then search: an error appears (timeout is
   20 seconds). Restore connectivity and press Search again to recover.
10. With results already visible, disable internet and select a different video:
    playback shows an error. Restore internet and tap Retry playback. Stream
    resolution times out after 30 seconds; player loading after another 20 seconds.
    Already-buffered audio may continue briefly when connectivity disappears.
11. Switch apps or lock the phone: playback pauses. Return and tap Play to resume.
    If loading finishes while the app is away, audio does not start automatically.
12. Let a short video finish: it stays stopped; Replay restarts that same video.

## Structure

- `lib/main.dart`: app entry and theme.
- `lib/screens/search_screen.dart`: local widget state and search/result UI.
- `lib/services/youtube_service.dart`: direct `youtube_explode_dart` search,
  first page only, and audio-only stream resolution with timeouts/client cleanup.
- `lib/services/playback_controller.dart`: one lazily created `just_audio` player,
  loading/error state, play/pause/replay, and foreground lifecycle handling.
- `lib/widgets/playback_bar.dart`: compact selected-video and playback controls.
- `lib/models/youtube_search_item.dart`: result fields and duration display.
- `test/search_screen_test.dart`: deterministic search-state checks.
- `test/playback_controller_test.dart`: playback and lifecycle checks using
  `test/helpers/fake_audio_player.dart` (no network or native player required).
- `integration_test/playback_smoke_test.dart`: optional real Android audio check.

Search uses [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart)
without an API key. Search and audio loading need internet access. Playback uses
[just_audio](https://pub.dev/packages/just_audio). No queue, background service,
media notification, storage, or authentication is implemented. State uses Flutter's
built-in widget state and `ChangeNotifier`, with no external state-management or
dependency-injection framework.

This milestone handles videos with a resolvable audio-only stream. Live streams,
restricted videos, or YouTube extraction failures can show a playback error;
there is no HLS, login, or alternate extraction fallback. Stream URLs are resolved
on demand and never stored. An Android device/emulator is required to verify
actual audio output; controller tests use a fake player.

Some YouTube audio URLs return HTTP 403 even after successful stream resolution.
This was reproduced with `lTRiuFIWV54` and is a known upstream limitation
([upstream report](https://github.com/Hexer10/youtube_explode_dart/issues/386)).
The app shows a retryable error; try a different video if retry also fails.
The live integration check uses `jNQXAC9IVRw` ("Me at the zoo").
Playback passes the resolved HTTPS URL directly to just_audio, preferring MP4
audio when available. There is no custom proxy, media caching, or download layer.

The dependency is pinned to **3.0.5**: live verification exposed a `getT`
`NoSuchMethodError` in 3.1.0's search parser. The service uses `searchContent`
with `TypeFilters.video` to avoid a separate upload-date parsing failure in
`search()` for results labeled "Streamed ...". It maps only the fields needed
by this milestone. Recheck these upstream issues before upgrading the package.
