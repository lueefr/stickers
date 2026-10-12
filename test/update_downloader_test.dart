import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/update/update_downloader.dart';

void main() {
  group('ApkDownloadProgress', () {
    test('reports a bounded fraction when content length is known', () {
      expect(
        const ApkDownloadProgress(receivedBytes: 25, totalBytes: 100).fraction,
        0.25,
      );
      expect(
        const ApkDownloadProgress(receivedBytes: 120, totalBytes: 100).fraction,
        1.0,
      );
    });

    test('reports indeterminate progress when content length is unknown', () {
      expect(
        const ApkDownloadProgress(receivedBytes: 25, totalBytes: null).fraction,
        isNull,
      );
      expect(
        const ApkDownloadProgress(receivedBytes: 25, totalBytes: 0).fraction,
        isNull,
      );
    });
  });

  test('rejects non-HTTPS download URLs', () async {
    await expectLater(
      ApkDownloader().download(
        Uri.parse('http://example.com/update.apk'),
        onProgress: (_) {},
      ),
      throwsA(isA<UpdateDownloadException>()),
    );
  });
}
