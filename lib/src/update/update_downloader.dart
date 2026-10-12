import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Bytes transferred while downloading an APK update.
class ApkDownloadProgress {
  const ApkDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int? totalBytes;

  /// `null` is reported when the server does not provide a content length.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    final value = receivedBytes / total;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }
}

class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => 'UpdateDownloadException: $message';
}

class UpdateDownloadCancelled implements Exception {
  const UpdateDownloadCancelled();
}

/// Downloads an APK into the app's private cache for the Android installer.
class ApkDownloader {
  ApkDownloader({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? getTemporaryDirectory;

  final Future<Directory> Function() _directoryProvider;
  HttpClient? _client;
  bool _cancelled = false;

  Future<File> download(
    Uri url, {
    required void Function(ApkDownloadProgress progress) onProgress,
  }) async {
    if (url.scheme != 'https' || url.host.isEmpty) {
      throw const UpdateDownloadException('The APK URL must use HTTPS.');
    }
    if (_client != null) {
      throw const UpdateDownloadException('An APK download is already running.');
    }

    _cancelled = false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      // APKs are already compressed. Keeping the response bytes untouched also
      // lets us compare the received byte count with Content-Length reliably.
      ..autoUncompress = false;
    _client = client;
    File? partialFile;

    try {
      final temporaryDirectory = await _directoryProvider();
      _throwIfCancelled();

      final updatesDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}updates',
      );
      await updatesDirectory.create(recursive: true);
      final apkFile = File(
        '${updatesDirectory.path}${Platform.pathSeparator}stickers-update.apk',
      );
      partialFile = File('${apkFile.path}.part');
      if (await partialFile.exists()) await partialFile.delete();
      _throwIfCancelled();

      final request = await client.getUrl(url).timeout(const Duration(seconds: 30));
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      request.headers.set(HttpHeaders.userAgentHeader, 'Stickers-Android-Updater');
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateDownloadException(
          'The APK server returned HTTP ${response.statusCode}.',
        );
      }

      final totalBytes = response.contentLength >= 0 ? response.contentLength : null;
      var receivedBytes = 0;
      onProgress(ApkDownloadProgress(receivedBytes: 0, totalBytes: totalBytes));

      final output = partialFile.openWrite();
      try {
        await for (final chunk in response.timeout(const Duration(seconds: 60))) {
          _throwIfCancelled();
          output.add(chunk);
          receivedBytes += chunk.length;
          onProgress(ApkDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ));
        }
        await output.flush();
      } finally {
        await output.close();
      }

      _throwIfCancelled();
      if (receivedBytes == 0) {
        throw const UpdateDownloadException('The downloaded APK is empty.');
      }
      if (totalBytes != null && receivedBytes != totalBytes) {
        throw const UpdateDownloadException('The APK download was incomplete.');
      }

      final signature = await partialFile.openRead(0, 2).fold<List<int>>(
        <int>[],
        (bytes, chunk) {
          bytes.addAll(chunk);
          return bytes;
        },
      );
      if (signature.length < 2 || signature[0] != 0x50 || signature[1] != 0x4b) {
        throw const UpdateDownloadException('The downloaded file is not an APK.');
      }

      if (await apkFile.exists()) await apkFile.delete();
      return await partialFile.rename(apkFile.path);
    } catch (error) {
      await _removePartialFile(partialFile);
      if (error is UpdateDownloadCancelled) rethrow;
      if (_cancelled) throw const UpdateDownloadCancelled();
      if (error is UpdateDownloadException) rethrow;
      if (error is TimeoutException) {
        throw const UpdateDownloadException('The APK download timed out.');
      }
      if (error is SocketException || error is HttpException) {
        throw const UpdateDownloadException('Could not connect to the APK server.');
      }
      throw UpdateDownloadException('Could not download the APK: $error');
    } finally {
      if (identical(_client, client)) _client = null;
      client.close(force: true);
    }
  }

  /// Aborts the in-flight request. Any partial file is removed before returning.
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const UpdateDownloadCancelled();
  }

  Future<void> _removePartialFile(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A partial cache file is harmless and will be removed before the next
      // download attempt.
    }
  }
}
