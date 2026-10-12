import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stickers/generated/intl/app_localizations.dart';

import 'update_downloader.dart';
import 'update_service.dart';

class UpdateDownloadDialog extends StatefulWidget {
  const UpdateDownloadDialog({
    super.key,
    required this.release,
  });

  final UpdateRelease release;

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  static const _methodChannel = MethodChannel('de.loicezt.stickers/methods');

  final _downloader = ApkDownloader();
  ApkDownloadProgress? _progress;
  File? _apkFile;
  bool _isDownloading = true;
  bool _downloadFailed = false;
  bool _isInstalling = false;
  String? _installErrorCode;
  DateTime _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_download());
    });
  }

  @override
  void dispose() {
    if (_isDownloading) _downloader.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    final apkUrl = widget.release.apkDownloadUrl;
    if (apkUrl == null) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadFailed = true;
      });
      return;
    }

    try {
      final file = await _downloader.download(
        apkUrl,
        onProgress: (progress) {
          if (!mounted) return;
          final now = DateTime.now();
          if (now.difference(_lastProgressUpdate) < const Duration(milliseconds: 100) &&
              progress.fraction != 1) {
            return;
          }
          _lastProgressUpdate = now;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _apkFile = file;
        _isDownloading = false;
        _downloadFailed = false;
      });
    } on UpdateDownloadCancelled {
      // The dialog is normally dismissed at the same time as cancellation.
      if (mounted) setState(() => _isDownloading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadFailed = true;
      });
    }
  }

  void _retryDownload() {
    setState(() {
      _progress = null;
      _apkFile = null;
      _isDownloading = true;
      _downloadFailed = false;
      _installErrorCode = null;
      _lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    });
    unawaited(_download());
  }

  void _cancelDownload() {
    _downloader.cancel();
    Navigator.of(context).pop();
  }

  Future<void> _install() async {
    final apkFile = _apkFile;
    if (apkFile == null || _isInstalling) return;

    setState(() {
      _isInstalling = true;
      _installErrorCode = null;
    });
    try {
      await _methodChannel.invokeMethod<void>('installApk', apkFile.path);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _isInstalling = false;
        _installErrorCode = error.code;
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _isInstalling = false;
        _installErrorCode = 'INSTALLER_UNAVAILABLE';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isInstalling = false;
        _installErrorCode = 'INSTALL_FAILED';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final title = _isDownloading
        ? strings.downloadingUpdate
        : _isInstalling
            ? strings.installUpdate
            : _downloadFailed
                ? strings.updateDownloadFailed
                : strings.updateDownloadComplete;

    return AlertDialog(
      title: Text(title),
      content: _buildContent(context, strings),
      actions: _buildActions(strings),
    );
  }

  Widget _buildContent(BuildContext context, AppLocalizations strings) {
    if (_isDownloading) {
      final progress = _progress;
      final fraction = progress?.fraction;
      final progressLabel = progress == null
          ? strings.updateDownloadBytesReceived(_formatBytes(0))
          : fraction == null
              ? strings.updateDownloadBytesReceived(
                  _formatBytes(progress.receivedBytes),
                )
              : strings.updateDownloadProgress(
                  _formatBytes(progress.receivedBytes),
                  _formatBytes(progress.totalBytes!),
                  '${(fraction * 100).round()}',
                );

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.downloadingUpdateMessage(widget.release.displayVersion)),
          const SizedBox(height: 20),
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              progressLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }

    if (_isInstalling) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Flexible(child: Text(strings.preparingUpdateInstaller)),
        ],
      );
    }

    if (_downloadFailed) return Text(strings.updateDownloadFailedMessage);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.updateDownloadedMessage(widget.release.displayVersion)),
        if (_installErrorCode != null) ...[
          const SizedBox(height: 12),
          Text(
            _installErrorCode == 'INSTALL_PERMISSION_DENIED'
                ? strings.updateInstallPermissionDeniedMessage
                : strings.updateInstallFailedMessage,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActions(AppLocalizations strings) {
    if (_isDownloading || _isInstalling) {
      return _isDownloading
          ? [
              TextButton(
                onPressed: _cancelDownload,
                child: Text(strings.cancel),
              ),
            ]
          : const <Widget>[];
    }

    if (_downloadFailed) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.later),
        ),
        FilledButton.icon(
          onPressed: _retryDownload,
          icon: const Icon(Icons.refresh),
          label: Text(strings.retry),
        ),
      ];
    }

    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(strings.later),
      ),
      FilledButton.icon(
        onPressed: _install,
        icon: const Icon(Icons.install_mobile),
        label: Text(strings.installUpdate),
      ),
    ];
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
