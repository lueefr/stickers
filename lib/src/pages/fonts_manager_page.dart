import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/dialogs/delete_confirm_dialog.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/settings/settings_page.dart';
import 'package:url_launcher/url_launcher.dart';

import 'fonts_search_page.dart';

class FontsManagerPage extends StatefulWidget {
  static const routeName = "${SettingsPage.routeName}/fonts";

  const FontsManagerPage({super.key});

  @override
  State<FontsManagerPage> createState() => _FontsManagerPageState();
}

class _FontsManagerPageState extends State<FontsManagerPage> {
  @override
  Widget build(BuildContext context) {
    return DefaultSliverActivity(
        title: AppLocalizations.of(context)!.fontsManager,
        child: ReorderableListView.builder(
          footer: ListTile(
            onTap: () async {
              final answer = settingsController.googleFonts ||
                  await showDialog(
                    context: context,
                    builder: (_) => GoogleFontsConfirmationDialog(),
                  );

              if (!context.mounted) return;
              if (answer != true) return;

              Navigator.of(context).push(MaterialPageRoute(builder: (context) => FontsSearchPage())).then((_) {
                setState(() {});
              });
            },
            leading: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: Icon(Icons.add),
            ),
            title: Text(AppLocalizations.of(context)!.addMore),
          ),
          buildDefaultDragHandles: false,
          itemCount: FontsRegistry.fontCount,
          onReorderStart: (i) {
            HapticFeedback.lightImpact();
          },
          itemBuilder: (context, i) {
            final entry = FontsRegistry.at(i);
            return ReorderableDelayedDragStartListener(
              index: i,
              key: ValueKey(entry.family),
              child: ListTile(
                onTap: () async {
                  var result =
                      await showDialog(context: context, builder: (context) => EditFontDialog(entry));
                  if (result == "") result = null;
                  entry.display = result;
                  FontsRegistry.enqueueSave();
                },
                leading: IconButton(
                  onPressed: () async {
                    final shouldDelete = await showDialog(
                        context: context, builder: (context) => DeleteConfirmDialog(entry.family));
                    if (shouldDelete) {
                      FontsRegistry.delete(entry.family);
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.delete),
                ),
                title: Text(
                  entry.family,
                  style: TextStyle(fontFamily: entry.family),
                ),
                trailing: ReorderableDragStartListener(
                  index: i,
                  child: Opacity(
                    opacity: .5,
                    child: Icon(Icons.reorder),
                  ),
                ),
              ),
            );
          },
          onReorder: (int oldIndex, int newIndex) {
            FontsRegistry.reorder(oldIndex, newIndex);
            setState(() {});
          },
        ));
  }
}

class EditFontDialog extends StatefulWidget {
  final FontsRegistryEntry entry;

  const EditFontDialog(
    this.entry, {
    super.key,
  });

  @override
  State<EditFontDialog> createState() => _EditFontDialogState();
}

class _EditFontDialogState extends State<EditFontDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    _controller = TextEditingController(text: widget.entry.display);
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Center(
        child: Text(
          widget.entry.family,
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: widget.entry.family),
        ),
      ),
      content: TextField(
        controller: _controller,
        style: TextStyle(fontFamily: widget.entry.family),
        decoration: InputDecoration(label: Text(AppLocalizations.of(context)!.displayName)),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(_controller.text);
          },
          child: Text(AppLocalizations.of(context)!.done),
        ),
      ],
    );
  }
}

class GoogleFontsConfirmationDialog extends StatelessWidget {
  const GoogleFontsConfirmationDialog({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Text(AppLocalizations.of(context)!.privacyNotice),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context)!.privacyNoticeText),
          TextButton.icon(
            icon: Icon(Icons.open_in_new),
            onPressed: () {
              launchUrl(Uri.parse("https://developers.google.com/fonts/faq/privacy"));
            },
            label: Text(AppLocalizations.of(context)!.moreInfo),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
          },
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(true);
            settingsController.updateGoogleFonts(true);
          },
          child: Text(AppLocalizations.of(context)!.continue_),
        ),
      ],
    );
  }
}
