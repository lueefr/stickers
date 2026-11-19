import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Where the animated-sticker flows (video and GIF) read their media from.
///
/// The platform pickers cannot run in a widget test, so the choice of a source
/// lives behind one small seam: [instance] can be replaced to drive the flow
/// deterministically. Production always uses [PlatformStickerMediaSources].
abstract class StickerMediaSources {
  static StickerMediaSources instance = const PlatformStickerMediaSources();

  /// Path of the video the user picked, or `null` when they picked nothing.
  Future<String?> pickVideo();

  /// Path of the GIF the user picked, or `null` when they picked nothing.
  Future<String?> pickGif();
}

/// The real pickers: the system gallery for videos, the system file picker
/// (filtered to `.gif`) for GIFs.
class PlatformStickerMediaSources implements StickerMediaSources {
  const PlatformStickerMediaSources();

  @override
  Future<String?> pickVideo() async {
    final XFile? video = await ImagePicker().pickVideo(source: ImageSource.gallery);
    return video?.path;
  }

  @override
  Future<String?> pickGif() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ["gif"],
    );
    return file?.path;
  }
}
