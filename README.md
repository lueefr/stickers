AI HAS BEEN USED

## Building

```sh
flutter pub get
flutter build apk --release
```

### Android toolchain

The Flutter Gradle plugin refuses to build below hard minimums — the current
stable SDK (3.47.2) requires Gradle 8.14, AGP 8.11.1 and Kotlin 2.2.20 — so the
Android side is pinned to:

| Where | What | Version |
| --- | --- | --- |
| `android/gradle/wrapper/gradle-wrapper.properties` | Gradle | 8.14.4 |
| `android/settings.gradle` | Android Gradle Plugin | 8.13.2 |
| `android/settings.gradle` | Kotlin Gradle plugin | 2.4.0 |

Those three are the combination Flutter's own tooling accepts *and* that the
Kotlin Gradle plugin 2.4.0 fully supports (Gradle 7.6.3–9.5.0, AGP 8.5.2–9.1.0),
so no AGP 9 / `android.newDsl` migration is needed. Newer Gradle/AGP/Kotlin are
only *suggested* by `flutter analyze --suggestions` — those hints are warnings
and do not fail the build.

`python3 tool/check_android_versions.py` re-checks the three files against the
thresholds the Flutter tool enforces (plus the signing-config guard below).

### Release signing (optional)

`android/key.properties` is gitignored, so a fresh checkout builds an *unsigned*
release APK and just prints a warning. To produce a signed, publishable build,
create `android/key.properties` (the folder that also contains `app/build.gradle`):

```properties
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=<key alias>
storeFile=<path to the .jks/.keystore>
```

`storeFile` may be absolute or relative to `android/`.

### Google Fonts search (optional)

Browsing/downloading Google Fonts inside the app requires a free
[Google Fonts Developer API key](https://developers.google.com/fonts/docs/developer_api).
Pass it at build time — without it the app still builds and runs, only the
font list download is disabled (a previously cached list keeps working):

```sh
flutter build apk --release --dart-define=GOOGLE_FONTS_API_KEY=<your-key>
```

`build_all.cmd` (Windows) and `build_all.sh` (Linux/macOS) build the split-per-abi
APKs, the combined APK and the app bundle, and pick the key up from a
`GOOGLE_FONTS_API_KEY` environment variable automatically:

```sh
GOOGLE_FONTS_API_KEY=<your-key> ./build_all.sh   # Linux/macOS
set GOOGLE_FONTS_API_KEY=<your-key> && build_all.cmd   # Windows
```

### Troubleshooting

`Error when reading 'lib/src/api_keys.dart'` or `'ImageSource' is imported from
both ...` means the checkout predates commit `1c7f0bf`, where the API key moved to
a `--dart-define`. Update the checkout (or re-download it) and rebuild; no file
has to be created by hand.
