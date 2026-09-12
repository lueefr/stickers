import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/data/load_store.dart';

/// 8x8 PNG with a 4x4 opaque square in the middle and a transparent margin
/// around it: the visible content is exactly 0.25..0.75 on both axes.
const String _kPngWithMargin =
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAFElEQVR42mNgoBr4D0TIeCAUkA0AcXgf4VSti+0AAAAASUVORK5CYII=';

/// 4x4 PNG that is fully opaque: there is nothing to trim.
const String _kPngOpaque =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAD0lEQVR42mNg+I8GSRcAACxQH+FFrzMQAAAAAElFTkSuQmCC';

/// 4x4 PNG that is fully transparent: there is no content at all.
const String _kPngTransparent =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAADElEQVR42mNgoBwAAABEAAHpHptRAAAAAElFTkSuQmCC';

void main() {
  // The checks below decode images, which needs the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  final Uint8List withMargin = base64Decode(_kPngWithMargin);
  final Uint8List opaque = base64Decode(_kPngOpaque);
  final Uint8List transparent = base64Decode(_kPngTransparent);

  group('visibleContentBounds', () {
    test('measures the content of an image with transparent margins', () async {
      final Rect? bounds = await visibleContentBounds(withMargin);

      expect(bounds, isNotNull);
      expect(bounds!.left, closeTo(.25, .001));
      expect(bounds.top, closeTo(.25, .001));
      expect(bounds.right, closeTo(.75, .001));
      expect(bounds.bottom, closeTo(.75, .001));
    });

    test('reports nothing to trim when the content covers the whole image', () async {
      expect(await visibleContentBounds(opaque), isNull);
    });

    test('reports nothing to trim for a fully transparent image', () async {
      expect(await visibleContentBounds(transparent), isNull);
    });

    test('reports nothing to trim for data that is not an image', () async {
      expect(await visibleContentBounds(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  group('rotatedImageSize', () {
    test('quarter turns swap the axes', () {
      final Size rotated = rotatedImageSize(const Size(4, 2), 90);

      expect(rotated.width, closeTo(2, 1e-9));
      expect(rotated.height, closeTo(4, 1e-9));
    });

    test('half turns and no rotation keep the size', () {
      final Size none = rotatedImageSize(const Size(4, 2), 0);
      expect(none.width, closeTo(4, 1e-9));
      expect(none.height, closeTo(2, 1e-9));

      final Size half = rotatedImageSize(const Size(4, 2), 180);
      expect(half.width, closeTo(4, 1e-9));
      expect(half.height, closeTo(2, 1e-9));
    });
  });

  group('stretchRegion', () {
    test('keeps the crop box the user narrowed', () async {
      const Rect box = Rect.fromLTWH(1, 2, 3, 2);

      expect(await stretchRegion(withMargin, const Size(8, 8), cropRect: box), box);
    });

    test('uses the content when the crop box still covers the whole image', () async {
      final Rect? region = await stretchRegion(
        withMargin,
        const Size(8, 8),
        cropRect: const Rect.fromLTWH(0, 0, 8, 8),
      );

      expect(region, isNotNull);
      expect(region!.left, closeTo(2, .01));
      expect(region.top, closeTo(2, .01));
      expect(region.right, closeTo(6, .01));
      expect(region.bottom, closeTo(6, .01));
    });

    test('keeps the crop box inside the image', () async {
      final Rect? region = await stretchRegion(
        withMargin,
        const Size(8, 8),
        cropRect: const Rect.fromLTWH(-1, -1, 4, 4),
      );

      expect(region, const Rect.fromLTRB(0, 0, 3, 3));
    });

    test('has no region to stretch when there is nothing to trim', () async {
      expect(await stretchRegion(opaque, const Size(4, 4)), isNull);
    });
  });

  group('stretchStickerToSquare', () {
    late ImageEditorPlatform original;
    late _RecordingEditor editor;

    setUp(() {
      original = ImageEditorPlatform.instance;
      editor = _RecordingEditor();
      ImageEditorPlatform.instance = editor;
    });

    tearDown(() {
      ImageEditorPlatform.instance = original;
    });

    test('stretches the region onto the 512x512 sticker canvas', () async {
      await stretchStickerToSquare(Uint8List.fromList([1]), 0, const Rect.fromLTWH(4, 8, 16, 32));

      final List<Option> options = editor.option!.options;
      expect(options, hasLength(2));
      final ClipOption clip = options[0] as ClipOption;
      expect([clip.x, clip.y, clip.width, clip.height], [4, 8, 16, 32]);
      final ScaleOption scale = options[1] as ScaleOption;
      expect([scale.width, scale.height], [512, 512]);
      expect(scale.keepRatio, isFalse);
    });

    test('rotates first and stretches the whole image without a region', () async {
      await stretchStickerToSquare(Uint8List.fromList([1]), 90);

      final List<Option> options = editor.option!.options;
      expect(options, hasLength(2));
      expect((options[0] as RotateOption).degree, 90);
      expect(options[1], isA<ScaleOption>());
      expect(options.whereType<ClipOption>(), isEmpty);
    });
  });
}

/// Records the options the app asks the image editor for.
class _RecordingEditor extends UnsupportedImageEditor {
  ImageEditorOption? option;

  @override
  Future<Uint8List?> editImage({
    required Uint8List image,
    required ImageEditorOption imageEditorOption,
  }) async {
    option = imageEditorOption;
    return Uint8List.fromList([1, 2, 3]);
  }
}
