import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/create_pack_dialog.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/util.dart';
import 'package:stickers/src/widgets/sticker_pack_preview_card.dart';

class StickerPacksPage extends StatefulWidget {
  const StickerPacksPage({super.key});

  static const routeName = "/";

  @override
  State<StickerPacksPage> createState() => StickerPacksPageState();
}

class StickerPacksPageState extends State<StickerPacksPage> {
  final Set<StickerPack> _selectedPacks = <StickerPack>{};

  bool get _selectionMode => _selectedPacks.isNotEmpty;

  @override
  initState() {
    super.initState();
    homeState = this;
  }

  void update() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultSliverActivity(
      leading: _selectionMode
          ? IconButton(
              tooltip: AppLocalizations.of(context)!.cancel,
              onPressed: () {
                setState(() => _selectedPacks.clear());
              },
              icon: const Icon(Icons.close),
            )
          : null,
      actions: _selectionMode
          ? [
              IconButton(
                tooltip: "Select all",
                onPressed: () {
                  setState(() {
                    _selectedPacks
                      ..clear()
                      ..addAll(packs);
                  });
                },
                icon: const Icon(Icons.select_all),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context)!.addToWhatsapp,
                onPressed: _sendSelectedToWhatsapp,
                icon: const Icon(Icons.send),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context)!.export,
                onPressed: _exportSelected,
                icon: const Icon(Icons.share),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context)!.delete,
                onPressed: _deleteSelected,
                icon: const Icon(Icons.delete),
              ),
            ]
          : [
              IconButton(
                tooltip: "Select packs",
                onPressed: () {
                  if (packs.isNotEmpty) {
                    setState(() => _selectedPacks.add(packs.first));
                  }
                },
                icon: const Icon(Icons.checklist),
              ),
              IconButton(
                tooltip: AppLocalizations.of(context)!.settings,
                onPressed: () {
                  Navigator.of(context).pushNamed("/settings");
                },
                icon: const Icon(Icons.settings),
              )
            ],
      fab: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            tooltip: AppLocalizations.of(context)!.import,
            onPressed: () async {
              FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.any,
                  allowMultiple: true,
                  dialogTitle: AppLocalizations.of(context)!.selectPack);
              if (result == null) return;
              for (final f in result.files) {
                try {
                  await importPack(File(f.path!));
                  setState(() {});
                } on Exception catch (e, st) {
                  debugPrint(e.toString());
                  debugPrintStack(stackTrace: st);
                  if (!context.mounted) return;
                  showDialog(
                      context: context,
                      builder: (context) => ErrorDialog(
                          title: AppLocalizations.of(context)!.couldntImportPack,
                          message: AppLocalizations.of(context)!.checkPack));
                }
              }
              setState(() {});
            },
            mini: true,
            child: const Icon(Icons.upload_file),
          ),
          SizedBox(
            width: 8,
          ),
          FloatingActionButton.extended(
            backgroundColor: Theme.of(context).colorScheme.primary,
            onPressed: () {
              showDialog(context: context, builder: (_) => CreatePackDialog(packs)).then(
                (_) => setState(() {
                  savePacks(packs);
                }),
              );
            },
            icon: Icon(
              Icons.add,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            label: Text(
              AppLocalizations.of(context)!.createPack,
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            ),
          ),
        ],
      ),
      title: _selectionMode
          ? "${_selectedPacks.length} selected"
          : AppLocalizations.of(context)?.pTitle ?? localizationUnavailable,
      child: packs.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(8, 36, 8, 0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.noPacks,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Opacity(
                    opacity: .8,
                    child: Text(
                      AppLocalizations.of(context)!.clickOnTheBottomRightToAddAStickerPack,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              separatorBuilder: (context, index) => Container(),
              itemBuilder: (context, index) => StickerPackPreviewCard(
                packs[index],
                () {
                  _selectedPacks.remove(packs[index]);
                  setState(() {});
                },
                selectionMode: _selectionMode,
                selected: _selectedPacks.contains(packs[index]),
                onSelectionChanged: () => _toggleSelection(packs[index]),
                onLongPress: () => _toggleSelection(packs[index]),
              ),
              itemCount: packs.length,
            ),
    );
  }

  void _toggleSelection(StickerPack pack) {
    setState(() {
      if (_selectedPacks.contains(pack)) {
        _selectedPacks.remove(pack);
      } else {
        _selectedPacks.add(pack);
      }
    });
  }

  Future<void> _sendSelectedToWhatsapp() async {
    final selected = _selectedPacks.toList();
    for (final pack in selected) {
      if (!mounted) return;
      await sendToWhatsappWithErrorHandling(pack, context);
    }
  }

  Future<void> _exportSelected() async {
    final selected = _selectedPacks.toList();
    for (final pack in selected) {
      await exportPack(pack);
    }
  }

  Future<void> _deleteSelected() async {
    final selected = _selectedPacks.toList();
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete ${selected.length} packs?"),
        content: Text("This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(AppLocalizations.of(context)!.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(AppLocalizations.of(context)!.delete)),
        ],
      ),
    );
    if (answer != true) return;
    for (final pack in selected) {
      packs.remove(pack);
      try {
        await Directory("$packsDir/${pack.id}").delete(recursive: true);
      } on FileSystemException catch (_) {}
    }
    _selectedPacks.clear();
    savePacks(packs);
    setState(() {});
  }
}
