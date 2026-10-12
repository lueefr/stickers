import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/video/common.dart';

/// WhatsApp validates every sticker of a pack and refuses the whole pack when
/// one of them breaks a rule. The animated sticker limits are therefore not a
/// detail of the encoder: media that cannot become a valid sticker has to be
/// cut (or refused) *before* it is added to a pack, which is what these helpers
/// are for.
void main() {
  test('the frame duration rule matches WhatsApp frame rate limit', () {
    // WhatsApp: no frame of an animated sticker may be shorter than 8 ms.
    expect(minAnimatedFrameDurationMs, 8);
    expect(maxAnimatedStickerFrameRate, 125);
  });

  group('clampAnimatedDuration', () {
    test('keeps a duration that already fits', () {
      expect(clampAnimatedDuration(const Duration(seconds: 3)), const Duration(seconds: 3));
      expect(clampAnimatedDuration(const Duration(seconds: 10)), const Duration(seconds: 10));
    });

    test('caps a longer duration at the limit', () {
      expect(clampAnimatedDuration(const Duration(seconds: 11)), maxAnimatedStickerDuration);
      expect(clampAnimatedDuration(const Duration(minutes: 5)), maxAnimatedStickerDuration);
    });
  });

  group('initialTrimEndFraction', () {
    test('keeps the whole video when it fits the limit', () {
      expect(initialTrimEndFraction(const Duration(milliseconds: 2500)), 1);
      expect(initialTrimEndFraction(const Duration(seconds: 10)), 1);
      // An unknown length must not trim anything either.
      expect(initialTrimEndFraction(Duration.zero), 1);
    });

    test('starts on the first ten seconds of a longer video', () {
      expect(initialTrimEndFraction(const Duration(seconds: 20)), closeTo(.5, 1e-9));
      expect(initialTrimEndFraction(const Duration(seconds: 60)), closeTo(1 / 6, 1e-9));
      expect(initialTrimEndFraction(const Duration(minutes: 10)), closeTo(1 / 60, 1e-9));
    });
  });

  group('clampAnimatedTrimWindow', () {
    const oneMinute = Duration(seconds: 60);
    // 10s of a 60s video.
    const limit = 1 / 6;

    test('leaves a window that fits the limit alone', () {
      final window = clampAnimatedTrimWindow(
        start: .1,
        end: .2,
        videoDuration: oneMinute,
        movedEnd: true,
      );
      expect(window.start, closeTo(.1, 1e-9));
      expect(window.end, closeTo(.2, 1e-9));
    });

    test('pulls the dragged end back to the limit', () {
      final window = clampAnimatedTrimWindow(
        start: .5,
        end: 1,
        videoDuration: oneMinute,
        movedEnd: true,
      );
      expect(window.start, closeTo(.5, 1e-9), reason: 'the start the user chose stays put');
      expect(window.end - window.start, closeTo(limit, 1e-9));
    });

    test('pulls the dragged start forward to the limit', () {
      final window = clampAnimatedTrimWindow(
        start: 0,
        end: .8,
        videoDuration: oneMinute,
        movedEnd: false,
      );
      expect(window.end, closeTo(.8, 1e-9), reason: 'the end the user chose stays put');
      expect(window.end - window.start, closeTo(limit, 1e-9));
    });

    test('never leaves the video, whichever handle is dragged', () {
      for (final movedEnd in [true, false]) {
        // The whole video selected: the longest window there is.
        final window = clampAnimatedTrimWindow(
          start: 0,
          end: 1,
          videoDuration: oneMinute,
          movedEnd: movedEnd,
        );
        expect(window.start, greaterThanOrEqualTo(0));
        expect(window.end, lessThanOrEqualTo(1));
        expect(window.end - window.start, closeTo(limit, 1e-9));
      }
    });

    test('leaves videos that fit the limit untouched', () {
      final window = clampAnimatedTrimWindow(
        start: .2,
        end: 1,
        videoDuration: const Duration(seconds: 5),
        movedEnd: true,
      );
      expect(window.start, closeTo(.2, 1e-9));
      expect(window.end, 1);
    });

    test('does not trim a video of unknown length', () {
      final window = clampAnimatedTrimWindow(
        start: 0,
        end: 1,
        videoDuration: Duration.zero,
        movedEnd: true,
      );
      expect(window.start, 0);
      expect(window.end, 1);
    });
  });
}
