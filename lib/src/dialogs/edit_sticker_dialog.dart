import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/sticker_pack.dart';

/// The widget shown when a sticker is tapped inside a pack page.
///
/// It previews the sticker over a transparency checkerboard, lets the user
/// change the associated emojis, delete the sticker, or jump to the crop
/// screen (the "edit" action, resolved by the caller through the returned
/// `"edit"` result).
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

  /// Shows the sticker editor and resolves with `"edit"` when the user asks
  /// to edit the sticker, or `null` otherwise (dismissed / saved / deleted).
  static Future<String?> show(BuildContext context, StickerPack pack, int index) {
    return showModalBottomSheet<String>(
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
              child: CustomPaint(
                painter: CheckerPainter(context),
                child: Image.file(
                  File(widget.pack.stickers[widget.index].source),
                  width: double.infinity,
                  height: 256,
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                ),
              ),
            ),
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
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop("edit");
                    },
                    icon: const Icon(Icons.edit),
                    label: Text(l10n.edit),
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
