import 'package:flutter/services.dart';
import 'package:stickers/src/video/common.dart';

class GifToWebPService {
  static const _methodChannel = MethodChannel('de.loicezt.stickers/methods');

  Future<void> convert({
    required String inputFile,
    required String outputFile,
    required double quality,
    required int fps,
  }) async {
    await _methodChannel.invokeMethod('convertGif', {
      'inputFile': inputFile,
      'outputFile': outputFile,
      'fps': fps,
      'config': WebPConfig(
        lossless: false,
        quality: quality,
        alphaCompression: 1,
        method: 4,
      ).toMap(),
    });
  }
}
