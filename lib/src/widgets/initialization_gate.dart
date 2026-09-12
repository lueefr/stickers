import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';

/// Defers editor-only resources until their first use. The builder is not
/// evaluated until initialization succeeds, so fast navigation cannot read a
/// partially initialized registry. Rebuilds do not restart the work.
class InitializationGate extends StatefulWidget {
  const InitializationGate({super.key, required this.initialize, required this.builder});

  final Future<void> Function() initialize;
  final WidgetBuilder builder;

  @override
  State<InitializationGate> createState() => _InitializationGateState();
}

class _InitializationGateState extends State<InitializationGate> {
  late Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = Future<void>.sync(widget.initialize);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError) {
            return widget.builder(context);
          }
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: snapshot.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline),
                        IconButton(
                          tooltip: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
                          onPressed: () => setState(() {
                            _ready = Future<void>.sync(widget.initialize);
                          }),
                          icon: const Icon(Icons.refresh),
                        ),
                        Text(AppLocalizations.of(context)!.error),
                      ],
                    )
                  : const CircularProgressIndicator(),
            ),
          );
        },
      );
}
