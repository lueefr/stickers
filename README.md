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

On Windows, `build_all.cmd` picks the key up from a `GOOGLE_FONTS_API_KEY`
environment variable automatically.
