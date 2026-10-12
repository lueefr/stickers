// Limits WhatsApp enforces on every sticker of a pack, taken from its own
// validator (StickerPackValidator in WhatsApp/stickers). One sticker that
// breaks a rule makes WhatsApp refuse the whole pack, so a video or a GIF that
// produces such a sticker can never be turned into a usable sticker until the
// media is cut to fit.
//
// - an animated sticker lasts at most 10 seconds and is at most 500 KiB;
// - no frame of it may be shorter than 8 ms (i.e. at most 125 fps);
// - a tray image is at most 50 KiB and a static sticker at most 100 KiB.
const int maxAnimatedStickerDurationMs = 10 * 1000;
const int maxAnimatedStickerBytes = 500 * 1024;
const int minAnimatedFrameDurationMs = 8;
const int maxAnimatedStickerFrameRate = 1000 ~/ minAnimatedFrameDurationMs;

/// [maxAnimatedStickerDurationMs] as a [Duration].
const Duration maxAnimatedStickerDuration = Duration(milliseconds: maxAnimatedStickerDurationMs);

/// Shortens [duration] to WhatsApp's [maxAnimatedStickerDuration].
Duration clampAnimatedDuration(Duration duration) =>
    duration > maxAnimatedStickerDuration ? maxAnimatedStickerDuration : duration;

/// Fraction of a video the trimmer may select when it starts: the whole video,
/// or only its first [maxAnimatedStickerDurationMs] when it is longer.
///
/// A sticker longer than that makes WhatsApp refuse the pack it belongs to, so
/// the trimmer starts on a window that can actually become a sticker.
double initialTrimEndFraction(Duration videoDuration) {
  final int durationMs = videoDuration.inMilliseconds;
  if (durationMs <= maxAnimatedStickerDurationMs) return 1;
  return maxAnimatedStickerDurationMs / durationMs;
}

/// The part of a video an animated sticker is made of, as fractions of the
/// video (0 is its start, 1 its end).
class AnimatedTrimWindow {
  const AnimatedTrimWindow({required this.start, required this.end});

  final double start;
  final double end;
}

/// Clamps a trim window, given as fractions ([start], [end]) of
/// [videoDuration], to WhatsApp's animated sticker duration limit.
///
/// [movedEnd] says which handle the user is dragging: the window is shortened
/// by pulling the *moved* handle back, so the other one stays where the user
/// put it and the slider keeps following the finger until it hits the limit.
AnimatedTrimWindow clampAnimatedTrimWindow({
  required double start,
  required double end,
  required Duration videoDuration,
  required bool movedEnd,
}) {
  final int durationMs = videoDuration.inMilliseconds;
  // `num.clamp` does not guarantee a double, so the result is converted back:
  // the window is handed to RangeSlider, which only takes doubles.
  double windowStart = start.clamp(0.0, 1.0).toDouble();
  double windowEnd = end.clamp(0.0, 1.0).toDouble();
  if (windowEnd < windowStart) {
    windowEnd = windowStart;
  }
  // Without a known length there is no fraction to compare with: leave the
  // window alone and let the native side clamp what it transcodes.
  if (durationMs <= maxAnimatedStickerDurationMs) {
    return AnimatedTrimWindow(start: windowStart, end: windowEnd);
  }

  final double limit = maxAnimatedStickerDurationMs / durationMs;
  if (windowEnd - windowStart <= limit) {
    return AnimatedTrimWindow(start: windowStart, end: windowEnd);
  }

  // Only the handle that is being dragged moves: it stops the limit short of
  // the other one, which stays where the user put it. This can never leave the
  // video: the fixed handle is inside it, and a window that would need to end
  // outside of it is shorter than the limit and returned above.
  if (movedEnd) {
    windowEnd = windowStart + limit;
  } else {
    windowStart = windowEnd - limit;
  }
  // Rounding only, so the value handed to RangeSlider is always in range.
  return AnimatedTrimWindow(
    start: windowStart.clamp(0.0, 1.0).toDouble(),
    end: windowEnd.clamp(0.0, 1.0).toDouble(),
  );
}

// Enums and classes to mirror the Kotlin side
enum Status {
  idle,
  running,
  success,
  failed,
  cancelled;

  /// Parses the status name reported by the platform channel.
  ///
  /// The Kotlin side declares its enums in `SCREAMING_CASE`, so the lookup
  /// ignores case instead of mirroring the constant names here.
  static Status fromName(String? name) => Status.values.firstWhere(
        (e) => e.name.toUpperCase() == name?.toUpperCase(),
        orElse: () => Status.idle,
      );
}

class Progress {
  final Status status;
  final double progress;
  final int currentFrame;
  final int totalFrames;

  Progress({
    this.status = Status.idle,
    this.progress = 0.0,
    this.currentFrame = 0,
    this.totalFrames = 0,
  });

  @override
  String toString() {
    return 'Progress{status: $status, progress: $progress, currentFrame: $currentFrame, totalFrames: $totalFrames}';
  }
}

enum WebPImageHint {
  defaultHint,
  picture,
  photo,
  graph,
}

class WebPConfig {
  final bool? lossless;
  final double? quality;
  final int? method;
  final WebPImageHint? imageHint;
  final int? targetSize;
  final double? targetPSNR;
  final int? segments;
  final int? snsStrength;
  final int? filterStrength;
  final int? filterSharpness;
  final int? filterType;
  final bool? autofilter;
  final int? alphaCompression;
  final int? alphaFiltering;
  final int? alphaQuality;
  final int? pass;
  final bool? showCompressed;
  final int? preprocessing;
  final int? partitions;
  final int? partitionLimit;
  final bool? emulateJpegSize;
  final bool? threadLevel;
  final bool? lowMemory;
  final int? nearLossless;
  final bool? exact;

  const WebPConfig({
    this.lossless,
    this.quality,
    this.method,
    this.imageHint,
    this.targetSize,
    this.targetPSNR,
    this.segments,
    this.snsStrength,
    this.filterStrength,
    this.filterSharpness,
    this.filterType,
    this.autofilter,
    this.alphaCompression,
    this.alphaFiltering,
    this.alphaQuality,
    this.pass,
    this.showCompressed,
    this.preprocessing,
    this.partitions,
    this.partitionLimit,
    this.emulateJpegSize,
    this.threadLevel,
    this.lowMemory,
    this.nearLossless,
    this.exact,
  });

  Map<String, dynamic> toMap() {
    return {
      'lossless': lossless,
      'quality': quality,
      'method': method,
      'imageHint': imageHint?.name,
      'targetSize': targetSize,
      'targetPSNR': targetPSNR,
      'segments': segments,
      'snsStrength': snsStrength,
      'filterStrength': filterStrength,
      'filterSharpness': filterSharpness,
      'filterType': filterType,
      'autofilter': autofilter,
      'alphaCompression': alphaCompression,
      'alphaFiltering': alphaFiltering,
      'alphaQuality': alphaQuality,
      'pass': pass,
      'showCompressed': showCompressed,
      'preprocessing': preprocessing,
      'partitions': partitions,
      'partitionLimit': partitionLimit,
      'emulateJpegSize': emulateJpegSize,
      'threadLevel': threadLevel,
      'lowMemory': lowMemory,
      'nearLossless': nearLossless,
      'exact': exact,
    }..removeWhere((key, value) => value == null);
  }
}
