import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:share_handler/share_handler.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/dialogs/eyedropper_dialog.dart';
import 'package:stickers/src/widgets/initialization_gate.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/edit_page.dart';
import 'package:stickers/src/pages/fonts_manager_page.dart';
import 'package:stickers/src/pages/select_pack_page.dart';
import 'package:stickers/src/pages/sticker_pack_page.dart';
import 'package:stickers/src/pages/sticker_packs_page.dart';
import 'package:stickers/src/pages/video_crop_page.dart';
import 'package:stickers/src/update/update_ui.dart';
import 'package:stickers/src/util.dart';

import 'settings/settings_controller.dart';
import 'settings/settings_page.dart';

/// The Widget that configures your application.
class StickersApp extends StatefulWidget {
  static StickersAppState? of(BuildContext context) => context.findAncestorStateOfType<StickersAppState>();

  const StickersApp({
    super.key,
    required this.settingsController,
  });

  final SettingsController settingsController;

  @override
  State<StickersApp> createState() => StickersAppState();
}

class StickersAppState extends State<StickersApp> {
  static final ThemeData _lightTheme = ThemeData();
  static final ThemeData _darkTheme = ThemeData.dark();

  /// The app language override; `null` means "follow the system language".
  late Locale? _locale;

  @override
  void initState() {
    super.initState();
    _locale = parseLocaleSetting(widget.settingsController.locale);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(initPlatformState());
      final updateContext = navigatorKey.currentContext;
      if (mounted && updateContext != null) {
        checkForAppUpdate(updateContext);
      }
    });
  }

  static Locale? parseLocaleSetting(String? language) =>
      (language == null || language == "system") ? null : Locale.fromSubtags(languageCode: language);

  void setLocale(Locale? value) {
    setState(() {
      _locale = value;
    });
  }

  SharedMedia? media;
  StreamSubscription<SharedMedia>? _shareSubscription;
  Future<void> _shareQueue = Future<void>.value();

  @override
  void dispose() {
    _shareSubscription?.cancel();
    super.dispose();
  }

  static Future<void> _prepareEditor() async {
    await Future.wait<void>([FontsRegistry.init(), GradientSliderTrackShape.prime()]);
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    final handler = ShareHandlerPlatform.instance;
    try {
      final initial = await handler.getInitialSharedMedia();
      if (!mounted) return;
      if (initial != null) _enqueueMedia(initial);
      _shareSubscription = handler.sharedMediaStream.listen(_enqueueMedia);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
    }
  }

  void _enqueueMedia(SharedMedia shared) {
    // A second share must not race an import/quick-add already saving packs.
    _shareQueue = _shareQueue.then((_) async {
      if (!mounted) return;
      navigatorKey.currentState!.popUntil((route) => route.isFirst);
      await _processMedia(shared);
      if (!mounted) return;
      final pending = media;
      media = null;
      if (pending != null) {
        unawaited(navigatorKey.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => SelectPackPage(pending)),
        ));
      }
      homeState?.update();
    }).catchError((Object error, StackTrace stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Glue the SettingsController to the MaterialApp.
    //
    // The ListenableBuilder Widget listens to the SettingsController for changes.
    // Whenever the user updates their settings, the MaterialApp is rebuilt.
    return ListenableBuilder(
      listenable: widget.settingsController,
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          // The "DEBUG" banner in the top right corner is not helpful here.
          debugShowCheckedModeBanner: false,

          // Providing a restorationScopeId allows the Navigator built by the
          // MaterialApp to restore the navigation stack when a user leaves and
          // returns to the app after it has been killed while running in the
          // background.
          restorationScopeId: 'app',

          // Provide the generated AppLocalizations to the MaterialApp. This
          // allows descendant Widgets to display the correct translations
          // depending on the user's locale.
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Automatically every language that has an ARB file in lib/l10n (see tool/translate.py).
          // If the device language has no translation, Flutter falls back to English.
          supportedLocales: AppLocalizations.supportedLocales,
          locale: _locale,

          // Use AppLocalizations to configure the correct application title
          // depending on the user's locale.
          //
          // The appTitle is defined in .arb files found in the localization
          // directory.
          onGenerateTitle: (BuildContext context) => AppLocalizations.of(context)!.appTitle,

          // Define a light and dark color theme. Then, read the user's
          // preferred ThemeMode (light, dark, or system default) from the
          // SettingsController to display the correct theme.
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: widget.settingsController.themeMode,
          navigatorKey: navigatorKey,

          // Define a function to handle named routes in order to support
          // Flutter web url navigation and deep linking.
          onGenerateRoute: (RouteSettings routeSettings) {
            return MaterialPageRoute<void>(
              settings: routeSettings,
              builder: (BuildContext context) {
                switch (routeSettings.name) {
                  case FontsManagerPage.routeName:
                    return InitializationGate(
                      initialize: FontsRegistry.init,
                      builder: (_) => const FontsManagerPage(),
                    );
                  case SettingsPage.routeName:
                    return SettingsPage(controller: widget.settingsController);
                  case VideoCropPage.routeName:
                    final args = routeSettings.arguments as EditArguments;
                    return VideoCropPage(
                      pack: args.pack,
                      index: args.index,
                      imagePath: args.mediaPath,
                    );
                  case CropPage.routeName:
                    final args = routeSettings.arguments as EditArguments;
                    return CropPage(
                      pack: args.pack,
                      index: args.index,
                      imagePath: args.mediaPath,
                    );
                  case EditPage.routeName:
                    final args = routeSettings.arguments as EditArguments;
                    return InitializationGate(
                      initialize: _prepareEditor,
                      builder: (_) => EditPage(args.pack, args.index, args.mediaPath, args.type, popCount: args.popCount),
                    );
                  case StickerPackPage.routeName:
                    return StickerPackPage(routeSettings.arguments as StickerPack, () {
                      setState(() {});
                    });
                  case StickerPacksPage.routeName:
                  default:
                    return const StickerPacksPage();
                }
              },
            );
          },
        );
      },
    );
  }

  Future<void> _processMedia(SharedMedia media) async {
    if (media.attachments == null || media.attachments!.isEmpty || media.attachments!.first == null) return;
    if (media.attachments!.first!.path.toLowerCase().endsWith(".stickify") ||
        media.attachments!.first!.path.toLowerCase().endsWith(".zip") ||
        media.attachments!.first!.path.toLowerCase().endsWith(".wastickers")) {
      try {
        await importPack(File(media.attachments!.first!.path));
        if (context.mounted) setState(() {});
      } on Exception catch (_) {
        if (mounted) {
          showDialog(
              context: navigatorKey.currentState!.context,
              builder: (context) => ErrorDialog(
                    message: AppLocalizations.of(context)!.checkIfFileValid,
                    title: AppLocalizations.of(context)!.importError,
                  ));
        }
      }
      return;
    }
    if (media.attachments!.first!.type != SharedAttachmentType.image) {
      if (mounted) {
        showDialog(
            context: navigatorKey.currentState!.context,
            builder: (context) => ErrorDialog(
                  message: AppLocalizations.of(context)!.unrecognizedFormat,
                  title: AppLocalizations.of(context)!.unrecognizedFormat,
                ));
      }
      return;
    }
    this.media = media;
    if (widget.settingsController.quickMode) {
      await _quickAdd(media, widget.settingsController.defaultTitle, widget.settingsController.defaultAuthor);
      this.media = null;
    }
  }

  Future<void> _quickAdd(SharedMedia media, String defaultTitle, String defaultAuthor) async {
    // Async read: this runs right after the app is resumed from a share, so a
    // synchronous read of the shared file would block the UI isolate for the
    // first frames of the navigation below.
    final rawImageData = await File(media.attachments!.first!.path).readAsBytes();
    final pack = packs.firstWhere((pack) => pack.stickers.length < 30 && !pack.animated, orElse: () {
      final pack = StickerPack(
        defaultTitle,
        defaultAuthor,
        "pack_${DateTime.now().millisecondsSinceEpoch}",
        [],
        "0",
        false, // TODO add support for animated stickers in auto-generated
      );
      packs.add(pack);
      savePacks(packs);
      return pack;
    });
    final index = pack.stickers.length;
    final img = await decodeImageFromList(rawImageData);
    final cropRect = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final cropped = await cropSticker(cropRect, rawImageData, pack, index, 0);
    await addToPack(pack, index, cropped);

    navigatorKey.currentState!.pushNamed("/pack", arguments: pack).then((value) {
      if (homeState != null) {
        homeState!.update();
      }
    });
    if (!mounted) return;
    await sendToWhatsappWithErrorHandling(pack, context);
  }
}
