import 'package:flutter/services.dart';
import 'package:stickers/src/video/common.dart';

class GifToWebPService {
  static const _methodChannel = MethodChannel('de.loicezt.stickers/methods');

  /// Converts the GIF at [inputFile] into an animated WebP written to
  /// [outputFile].
  ///
  /// The animation stops after [maxDurationMs]: WhatsApp refuses an animated
  /// sticker longer than ten seconds, and a rejected sticker makes the whole
  /// pack impossible to add, so a longer GIF is cut instead of being rejected.
  ///
  /// Returns the length of the *source* GIF in milliseconds, so the caller can
  /// tell the user when only a part of it became a sticker. Older native builds
  /// do not report it and a GIF without a duration returns 0.
  Future<int> convert({
    required String inputFile,
    required String outputFile,
    required double quality,
    required int fps,
    int maxDurationMs = maxAnimatedStickerDurationMs,
  }) async {
    final sourceDurationMs = await _methodChannel.invokeMethod<int>('convertGif', {
      'inputFile': inputFile,
      'outputFile': outputFile,
      'fps': fps,
      'maxDurationMs': maxDurationMs,
      'config': WebPConfig(
        lossless: false,
        quality: quality,
        alphaCompression: 1,
        method: 4,
      ).toMap(),
    });
    return sourceDurationMs ?? 0;
  }
}
