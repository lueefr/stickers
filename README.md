AI HAS BEEN USED

## Building

```sh
flutter pub get
flutter build apk --release
```

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
