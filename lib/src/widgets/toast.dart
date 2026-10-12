import 'package:flutter/material.dart';
import 'package:stickers/src/globals.dart';

/// Shows a short, non-blocking notice at the bottom of the screen.
///
/// The app reports failures in dialogs, but a step that worked can still need
/// an answer: the sticker was added to another pack, or only a part of the
/// source media fitted WhatsApp's limits. A dialog would interrupt the flow
/// that is already going on, so those are reported with a snack bar.
///
/// The notice is pushed through the root [ScaffoldMessenger] so it survives the
/// page that raised it (the pack the sticker went to) and never throws while
/// the app is tearing down, where a successful conversion would otherwise look
/// like a crash.
void showToast(String message) {
  final context = navigatorKey.currentContext;
  if (context == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  // Long enough to read a one-line message without covering the screen for
  // long. Snack bars queue up, so repeated messages are not lost.
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
