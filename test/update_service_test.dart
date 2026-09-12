import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/update/update_service.dart';

void main() {
  group('isNewerVersion', () {
    test('compares semantic versions before build numbers', () {
      expect(
        isNewerVersion(
          latestVersion: 'v1.6.0+1',
          currentVersion: '1.5.9',
          currentBuildNumber: '999',
        ),
        isTrue,
      );
      expect(
        isNewerVersion(
          latestVersion: 'v1.4.9+999',
          currentVersion: '1.5.0',
          currentBuildNumber: '1',
        ),
        isFalse,
      );
    });

    test('uses the build number when semantic versions match', () {
      expect(
        isNewerVersion(
          latestVersion: 'v1.5.0+19',
          currentVersion: '1.5.0',
          currentBuildNumber: '18',
        ),
        isTrue,
      );
      expect(
        isNewerVersion(
          latestVersion: 'v1.5.0+18',
          currentVersion: '1.5.0',
          currentBuildNumber: '18',
        ),
        isFalse,
      );
    });

    test('normalizes missing version parts and rejects malformed tags', () {
      expect(
        isNewerVersion(
          latestVersion: 'v2.0+1',
          currentVersion: '2.0.0',
          currentBuildNumber: '1',
        ),
        isFalse,
      );
      expect(
        isNewerVersion(
          latestVersion: 'latest',
          currentVersion: '1.0.0',
          currentBuildNumber: '1',
        ),
        isFalse,
      );
    });
  });

  group('UpdateRelease', () {
    test('parses release metadata and prefers the combined debug APK', () {
      final release = UpdateRelease.fromJson({
        'tag_name': 'v1.5.1+19',
        'html_url': 'https://github.com/lueefr/stickers/releases/tag/v1.5.1%2B19',
        'body': 'Fixes and improvements',
        'assets': [
          {
            'name': 'stickers-v1.5.1-19-arm64-v8a.apk',
            'browser_download_url': 'https://example.com/arm64.apk',
            'content_type': 'application/vnd.android.package-archive',
          },
          {
            'name': 'stickers-v1.5.1-19-debug.apk',
            'browser_download_url': 'https://example.com/debug.apk',
            'content_type': 'application/vnd.android.package-archive',
          },
        ],
      });

      expect(release.displayVersion, '1.5.1+19');
      expect(release.releaseNotes, 'Fixes and improvements');
      expect(release.apkDownloadUrl, Uri.parse('https://example.com/debug.apk'));
      expect(release.updateUrl, release.apkDownloadUrl);
    });

    test('falls back to release page when no APK is attached', () {
      final release = UpdateRelease.fromJson({
        'tag_name': 'v2.0.0+20',
        'html_url': 'https://example.com/release',
        'body': null,
        'assets': <Object>[],
      });

      expect(release.apkDownloadUrl, isNull);
      expect(release.updateUrl, Uri.parse('https://example.com/release'));
    });

    Map<String, dynamic> assets(List<String> names) => {
      'tag_name': 'v2.0.0+28',
      'html_url': 'https://example.com/release',
      'assets': names.map((name) => {
        'name': 'stickers-$name.apk',
        'browser_download_url': 'https://example.com/$name.apk',
      }).toList(),
    };

    test('prefers the device ABI release over universal and debug', () {
      final release = UpdateRelease.fromJson(assets([
        'universal-release', 'debug', 'armeabi-v7a-release', 'arm64-v8a-release', 'x86_64-release',
      ]), supportedAbis: ['arm64-v8a', 'armeabi-v7a']);
      expect(release.updateUrl.path, '/arm64-v8a-release.apk');
    });

    test('x86_64 is not confused with x86 or ARM', () {
      final release = UpdateRelease.fromJson(assets([
        'arm64-v8a-release', 'x86_64-release', 'universal-release',
      ]), supportedAbis: ['x86_64', 'x86']);
      expect(release.updateUrl.path, '/x86_64-release.apk');
    });

    test('unknown ABI falls back to universal release, not a random split', () {
      final release = UpdateRelease.fromJson(assets([
        'arm64-v8a-release', 'debug', 'universal-release',
      ]));
      expect(release.updateUrl.path, '/universal-release.apk');
    });

    test('an incompatible-only release opens its release page', () {
      final release = UpdateRelease.fromJson(assets(['arm64-v8a-release']),
          supportedAbis: ['armeabi-v7a']);
      expect(release.apkDownloadUrl, isNull);
      expect(release.updateUrl.path, '/release');
    });

    test('rejects malformed release metadata', () {
      expect(
        () => UpdateRelease.fromJson({'tag_name': 'v1.0.0'}),
        throwsFormatException,
      );
    });
  });
}
