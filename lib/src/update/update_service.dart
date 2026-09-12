import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String githubRepository = 'lueefr/stickers';
const String githubRepositoryUrl = 'https://github.com/$githubRepository';

/// Information about the newest stable release published on GitHub.
class UpdateRelease {
  const UpdateRelease({
    required this.tagName,
    required this.releaseUrl,
    required this.releaseNotes,
    this.apkDownloadUrl,
  });

  factory UpdateRelease.fromJson(Map<String, dynamic> json, {List<String> supportedAbis = const []}) {
    final tagName = json['tag_name'];
    final htmlUrl = json['html_url'];
    if (tagName is! String || tagName.isEmpty || htmlUrl is! String) {
      throw const FormatException('Invalid GitHub release response');
    }

    Uri? apkDownloadUrl;
    var bestAssetScore = -1;
    final assets = json['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name'];
        final downloadUrl = asset['browser_download_url'];
        if (name is! String || downloadUrl is! String || !name.toLowerCase().endsWith('.apk')) {
          continue;
        }

        final lowerName = name.toLowerCase();
        const knownAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'];
        // x86_64 must be tested before x86. Never offer an incompatible split,
        // even when it is the only asset. Unknown devices get the universal.
        String? abi;
        for (final candidate in knownAbis) {
          if (lowerName.contains(candidate)) {
            abi = candidate;
            break;
          }
        }
        if (abi != null && !supportedAbis.contains(abi)) continue;
        // Treat old shortened ABI filenames conservatively as split APKs too.
        if (abi == null && (lowerName.contains('arm64') || lowerName.contains('armeabi'))) continue;
        var score = abi == null ? 10 : 100 - supportedAbis.indexOf(abi);
        if (lowerName.contains('release')) score += 4;
        if (lowerName.contains('universal')) score += 2;
        if (lowerName.contains('debug')) score -= 2;

        if (score > bestAssetScore) {
          final parsedUrl = Uri.tryParse(downloadUrl);
          if (parsedUrl != null) {
            apkDownloadUrl = parsedUrl;
            bestAssetScore = score;
          }
        }
      }
    }

    return UpdateRelease(
      tagName: tagName,
      releaseUrl: Uri.parse(htmlUrl),
      releaseNotes: json['body'] is String ? json['body'] as String : '',
      apkDownloadUrl: apkDownloadUrl,
    );
  }

  final String tagName;
  final Uri releaseUrl;
  final String releaseNotes;
  final Uri? apkDownloadUrl;

  /// A tag such as `v1.5.1+19` is displayed as `1.5.1+19`.
  String get displayVersion => tagName.startsWith('v') || tagName.startsWith('V')
      ? tagName.substring(1)
      : tagName;

  /// Downloads the APK directly when one exists, otherwise opens the release page.
  Uri get updateUrl => apkDownloadUrl ?? releaseUrl;
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => 'UpdateCheckException: $message';
}

/// Reads the newest non-draft, non-prerelease version from GitHub Releases.
class UpdateService {
  const UpdateService({
    this.repository = githubRepository,
    this.timeout = const Duration(seconds: 15),
    this.supportedAbis = const [],
  });

  final String repository;
  final Duration timeout;
  final List<String> supportedAbis;

  Uri get latestReleaseApiUrl => Uri.https('api.github.com', '/repos/$repository/releases/latest');

  /// Returns `null` when the repository has not published a release yet.
  Future<UpdateRelease?> getLatestRelease() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(latestReleaseApiUrl).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Stickers-Android-Update-Checker');
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');

      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateCheckException('GitHub returned HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid GitHub release response');
      }
      return UpdateRelease.fromJson(decoded, supportedAbis: supportedAbis);
    } on TimeoutException catch (error) {
      throw UpdateCheckException('The GitHub request timed out: $error');
    } on SocketException catch (error) {
      throw UpdateCheckException('Could not connect to GitHub: $error');
    } on FormatException catch (error) {
      throw UpdateCheckException('Could not read the GitHub release: $error');
    } finally {
      client.close(force: true);
    }
  }

  Future<UpdateRelease?> findAvailableUpdate({
    required String currentVersion,
    required String currentBuildNumber,
  }) async {
    final release = await getLatestRelease();
    if (release == null) return null;
    return isNewerVersion(
      latestVersion: release.tagName,
      currentVersion: currentVersion,
      currentBuildNumber: currentBuildNumber,
    )
        ? release
        : null;
  }
}

/// Compares a GitHub release tag with the version reported by PackageInfo.
bool isNewerVersion({
  required String latestVersion,
  required String currentVersion,
  required String currentBuildNumber,
}) {
  final latest = _ComparableVersion.tryParse(latestVersion);
  final currentLabel = currentVersion.contains('+')
      ? currentVersion
      : '$currentVersion+$currentBuildNumber';
  final current = _ComparableVersion.tryParse(currentLabel);
  if (latest == null || current == null) return false;
  return latest.compareTo(current) > 0;
}

class _ComparableVersion implements Comparable<_ComparableVersion> {
  const _ComparableVersion(this.parts, this.buildNumber);

  static final RegExp _versionPattern = RegExp(
    r'^[vV]?(\d+(?:\.\d+)*)(?:-[0-9A-Za-z.-]+)?(?:\+(\d+))?$',
  );

  final List<int> parts;
  final int buildNumber;

  static _ComparableVersion? tryParse(String value) {
    final match = _versionPattern.firstMatch(value.trim());
    if (match == null) return null;

    final parts = match.group(1)!.split('.').map(int.parse).toList(growable: false);
    final buildNumber = int.tryParse(match.group(2) ?? '') ?? 0;
    return _ComparableVersion(parts, buildNumber);
  }

  @override
  int compareTo(_ComparableVersion other) {
    final length = parts.length > other.parts.length ? parts.length : other.parts.length;
    for (var index = 0; index < length; index++) {
      final left = index < parts.length ? parts[index] : 0;
      final right = index < other.parts.length ? other.parts[index] : 0;
      if (left != right) return left.compareTo(right);
    }
    return buildNumber.compareTo(other.buildNumber);
  }
}
