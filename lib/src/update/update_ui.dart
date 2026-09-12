import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/globals.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service.dart';

const _lastAutomaticCheckKey = 'lastAutomaticUpdateCheck';
const _automaticCheckInterval = Duration(hours: 12);
bool _checkInProgress = false;

/// Checks GitHub Releases and shows an update dialog when a newer APK exists.
///
/// Automatic checks are silent when there is no connection or no update, and
/// run at most twice per day. Checks started from Settings always show a result.
Future<void> checkForAppUpdate(
  BuildContext context, {
  bool userInitiated = false,
}) async {
  if (_checkInProgress) return;
  if (!userInitiated && !await _automaticCheckIsDue()) return;
  if (!context.mounted) return;
  _checkInProgress = true;

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (userInitiated) {
    messenger?.showSnackBar(
      SnackBar(
        duration: const Duration(minutes: 1),
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Text(AppLocalizations.of(context)!.checkingForUpdates),
          ],
        ),
      ),
    );
  }

  try {
    final packageInfo = info ?? await PackageInfo.fromPlatform();
    info ??= packageInfo;
    List<String> abis = const [];
    try {
      abis = await const MethodChannel('de.loicezt.stickers/methods')
          .invokeListMethod<String>('supportedAbis') ?? const [];
    } on PlatformException catch (_) {
      // Universal APK remains a safe fallback when ABI discovery fails.
    } on MissingPluginException catch (_) {
      // Non-Android test/development hosts.
    }
    final release = await UpdateService(supportedAbis: abis).findAvailableUpdate(
      currentVersion: packageInfo.version,
      currentBuildNumber: packageInfo.buildNumber,
    );
    if (!context.mounted) return;
    messenger?.hideCurrentSnackBar();

    final currentVersion = packageInfo.buildNumber.isEmpty
        ? packageInfo.version
        : '${packageInfo.version}+${packageInfo.buildNumber}';
    if (release == null) {
      if (userInitiated) await _showUpToDateDialog(context, currentVersion);
      return;
    }
    await _showUpdateDialog(context, release, currentVersion);
  } catch (_) {
    if (!context.mounted) return;
    messenger?.hideCurrentSnackBar();
    if (userInitiated) await _showCheckFailedDialog(context);
  } finally {
    _checkInProgress = false;
  }
}

Future<bool> _automaticCheckIsDue() async {
  final preferences = await SharedPreferences.getInstance();
  final now = DateTime.now().millisecondsSinceEpoch;
  final lastCheck = preferences.getInt(_lastAutomaticCheckKey);
  if (lastCheck != null && now - lastCheck < _automaticCheckInterval.inMilliseconds) {
    return false;
  }
  await preferences.setInt(_lastAutomaticCheckKey, now);
  return true;
}

Future<void> _showUpdateDialog(
  BuildContext context,
  UpdateRelease release,
  String currentVersion,
) async {
  final strings = AppLocalizations.of(context)!;
  var notes = release.releaseNotes.trim();
  if (notes.length > 4000) notes = '${notes.substring(0, 4000)}…';

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(strings.updateAvailable),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.updateAvailableMessage(
              release.displayVersion,
              currentVersion,
            ),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              strings.releaseNotes,
              style: Theme.of(dialogContext).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SelectableText(notes),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(strings.later),
        ),
        FilledButton.icon(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await _openUpdate(context, release.updateUrl);
          },
          icon: const Icon(Icons.download),
          label: Text(strings.downloadUpdate),
        ),
      ],
    ),
  );
}

Future<void> _showUpToDateDialog(BuildContext context, String currentVersion) {
  final strings = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.appIsUpToDate),
      content: Text(strings.appIsUpToDateMessage(currentVersion)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
        ),
      ],
    ),
  );
}

Future<void> _showCheckFailedDialog(BuildContext context) {
  final strings = AppLocalizations.of(context)!;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.updateCheckFailed),
      content: Text(strings.updateCheckFailedMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
        ),
      ],
    ),
  );
}

Future<void> _openUpdate(BuildContext context, Uri updateUrl) async {
  var opened = false;
  try {
    opened = await launchUrl(updateUrl, mode: LaunchMode.externalApplication);
  } catch (_) {
    // The error dialog below gives the user a localized, actionable result.
  }
  if (opened || !context.mounted) return;

  final strings = AppLocalizations.of(context)!;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings.error),
      content: Text(strings.couldntOpenUpdate),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
        ),
      ],
    ),
  );
}
