@echo off
REM builds and renames all apks and the appbudle
REM Set GOOGLE_FONTS_API_KEY before running to enable Google Fonts search
REM in the built app (get a key at
REM https://developers.google.com/fonts/docs/developer_api).

set "FONTS_KEY_ARG="
if defined GOOGLE_FONTS_API_KEY set "FONTS_KEY_ARG=--dart-define=GOOGLE_FONTS_API_KEY=%GOOGLE_FONTS_API_KEY%"

echo Cleaning...
call flutter clean

echo Building split per abi...
call flutter build apk --split-per-abi %FONTS_KEY_ARG%

echo Building combined apk...
call flutter build apk %FONTS_KEY_ARG%

echo Building bundle...
call flutter build appbundle %FONTS_KEY_ARG%

echo Renaming files...
for /F "tokens=* USEBACKQ" %%F in (`git rev-parse HEAD`) do (set sha=%%F)
set "sha=%sha:~0,7%"

ren .\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk stickers-%sha%-arm64-v8a.apk
ren .\build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk stickers-%sha%-armeabi-v7a.apk
ren .\build\app\outputs\flutter-apk\app-x86_64-release.apk stickers-%sha%-x86_64.apk
ren .\build\app\outputs\flutter-apk\app-release.apk stickers-%sha%.apk
echo Done !