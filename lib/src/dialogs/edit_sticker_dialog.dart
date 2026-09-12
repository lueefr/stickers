import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/widgets/sticker_thumbnail.dart';

/// What the user asked the sticker sheet to do with an existing sticker.
///
/// The sheet only reports the choice: it is dismissed before the action runs,
/// so the caller (the pack page) owns the navigation and uses its own
/// [BuildContext].
enum StickerSheetAction {
  /// Crop / stretch / rotate the sticker that is already in the pack, then
  /// write the result back over it.
  edit,

  /// Pick new media and put it in the same slot, replacing the old file while
  /// keeping the position and the associated emojis.
  replace,
}

/// The widget shown when a sticker is tapped inside a pack page.
///
/// It previews the sticker over a transparency checkerboard and offers every
/// action that can be performed on a sticker that is already in the pack:
/// crop/stretch it, replace it with new media, change its emojis, or delete
/// it. The media actions are resolved by the caller through the returned
/// [StickerSheetAction].
///
/// It is presented as a modal bottom sheet through [show]: the previous
/// implementation used `showDialog` + [AlertDialog], which on some devices
/// only ever displayed the dimmed barrier without the dialog itself (the
/// dialog route rendered but the card never became visible). Bottom sheets
/// use a different route mechanism that is already proven in this app (the
/// "new sticker" option sheet), so the widget now always appears.
class EditStickerDialog extends StatefulWidget {
  final StickerPack pack;
  final int index;

  const EditStickerDialog(this.pack, this.index, {super.key});

  /// Shows the sticker editor and resolves with the picked action, or `null`
  /// when the sheet was dismissed / the emojis were saved / the sticker was
  /// deleted (the caller only has to refresh its grid in those cases).
  static Future<StickerSheetAction?> show(BuildContext context, StickerPack pack, int index) {
    return showModalBottomSheet<StickerSheetAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => EditStickerDialog(pack, index),
    );
  }

  @override
  State<EditStickerDialog> createState() => _EditStickerDialogState();
}

class _EditStickerDialogState extends State<EditStickerDialog> {
  final formKey = GlobalKey<FormState>();
  final controller = TextEditingController();
  bool valid = true;

  /// Animated stickers are animated WebP files, and the crop screen runs them
  /// through the single-frame image editor: cropping one would silently
  /// flatten the animation into a still image. The video pipeline (the
  /// trimmer and the GIF converter) reads videos and GIFs only, so an
  /// animated sticker can be replaced but not re-cropped.
  bool get _canCrop => !widget.pack.animated;

  @override
  void initState() {
    super.initState();
    controller.text = widget.pack.stickers[widget.index].emojis.join();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SingleChildScrollView(
        // Keep the sheet usable while the emoji field raises the keyboard.
        padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.editSticker,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.antiAlias,
              child: StickerThumbnail(
                widget.pack.stickers[widget.index].source,
                width: double.infinity,
                height: 256,
                // Stickers are at most 512x512, so decoding at 512 is never an
                // upscale and keeps the preview sharp at any dialog width.
                cacheWidth: 512,
                cacheHeight: 512,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    // Disabled (not hidden) for animated stickers, together with
                    // the hint below, so the reason is obvious.
                    onPressed: _canCrop
                        ? () => Navigator.of(context).pop(StickerSheetAction.edit)
                        : null,
                    icon: const Icon(Icons.crop_free),
                    label: Text(l10n.edit),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(StickerSheetAction.replace),
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(l10n.replaceSticker),
                  ),
                ),
              ],
            ),
            if (!_canCrop) ...[
              const SizedBox(height: 8),
              Text(
                l10n.animatedStickerCropUnavailable,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: TextFormField(
                decoration: InputDecoration(label: Text(l10n.associatedEmojis)),
                textAlign: TextAlign.center,
                validator: validator,
                controller: controller,
                onChanged: (value) {
                  setState(() {
                    valid = validator(value) == null;
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 24),
              // Wrap instead of Row so the actions never overflow on
              // narrow screens ("RIGHT OVERFLOWED BY ... PIXELS").
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      File(widget.pack.stickers[widget.index].source).delete();
                      widget.pack.stickers.removeAt(widget.index);
                      widget.pack.onEdit();
                    },
                    child: Text(
                      l10n.deleteSticker,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                  FilledButton(
                    onPressed: valid
                        ? () {
                            if (formKey.currentState?.validate() == false) return;
                            widget.pack.stickers[widget.index].emojis =
                                controller.value.text.characters.toList();
                            widget.pack.onEdit();
                            Navigator.of(context).pop();
                          }
                        : null,
                    child: Text(l10n.done),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final RegExp _emojiRegex = RegExp(
      r"(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])");

  String? validator(String? value) {
    if (value == null || value.isEmpty) {
      return AppLocalizations.of(context)!.pleaseProvideAtLeastOneEmoji;
    } else if (value.characters.length > 3) {
      return AppLocalizations.of(context)!.pleaseProvideAtmost3Emojis;
    }
    for (final char in value.characters) {
      if (_emojiRegex.allMatches(char).isEmpty) {
        return AppLocalizations.of(context)!.pleaseEnterOnlyEmojis;
      }
    }
    return null;
  }
}
