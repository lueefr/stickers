import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/dialogs/edit_text_dialog.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/pages/edit_page.dart';

class EditorTextLayerData {
  EditorTextLayerData({
    required this.text,
    this.backgroundColor = Colors.transparent,
    this.backgroundPadding = 10,
    this.backgroundRadius = 16,
  });

  final EditorText text;
  Color backgroundColor;
  double backgroundPadding;
  double backgroundRadius;
}

class TextLayer extends StatefulWidget implements EditorLayer {
  final EditorTextLayerData data;

  /// Owned by this widget instance, so the editor can push transform updates
  /// into the mounted state without going through a [GlobalKey]. It is kept
  /// final because widgets have to stay immutable.
  final TextLayerState state = TextLayerState();

  EditorText get text => data.text;

  final Function(TextLayer)? onDelete;

  final GlobalKey rbKey;

  TextLayer(
    this.data, {
    super.key,
    this.onDelete,
    required this.rbKey,
  });

  @override
  // ignore: no_logic_in_create_state
  State<TextLayer> createState() => state;

  void update(Matrix4 matrix) {
    state.update(matrix);
  }
}

class TextLayerState extends State<TextLayer> {
  final TextEditingController _controller = TextEditingController(text: "");
  final _focusNode = FocusNode();
  final _editorKey = GlobalKey();
  late final ValueNotifier<Matrix4> _transform;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.text.text;
    _transform = ValueNotifier<Matrix4>(widget.text.transform);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) enableEditing();
    });
  }

  @override
  void didUpdateWidget(covariant TextLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data.text, widget.data.text)) {
      _transform.value = widget.text.transform;
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void enableEditing() {
    if (!mounted) return;
    showDialog(
      useRootNavigator: true,
      context: context,
      barrierDismissible: false,
      builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: TextEditingDialog(
          key: _editorKey,
          rbKey: widget.rbKey,
          disableEditing: disableEditing,
          controller: _controller,
          focusNode: _focusNode,
          parent: widget,
          onDelete: () {
            widget.onDelete?.call(widget);
          },
        ),
      ),
    ).then((value) {
      // Deleting the layer disposes this state while the dialog is closing.
      // Do not schedule a rebuild on a disposed state.
      if (!mounted) return;
      setState(() {
        widget.text.text = _controller.text;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = widget.text.fontSize * (FontsRegistry.sizeMultiplier(widget.text.fontName) ?? 1);
    final textStack = Stack(
      children: [
        Text(
          widget.text.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            inherit: false,
            fontSize: fontSize,
            foreground: Paint()
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round
              ..color = widget.text.outlineColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = widget.text.outlineWidth,
            fontFamily: widget.text.fontName,
          ),
        ),
        Text(
          _controller.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            inherit: false,
            fontSize: fontSize,
            color: widget.text.textColor,
            fontFamily: widget.text.fontName,
          ),
        ),
      ],
    );

    final textWidget = widget.data.backgroundColor == Colors.transparent
        ? textStack
        : Container(
            padding: EdgeInsets.all(widget.data.backgroundPadding),
            decoration: BoxDecoration(
              color: widget.data.backgroundColor,
              borderRadius: BorderRadius.circular(widget.data.backgroundRadius),
            ),
            child: textStack,
          );

    // Sticker text must render identically regardless of the system font
    // scaling, otherwise the design changes per device accessibility setting.
    // The repaint boundary is inside the transform so dragging a layer can
    // reuse its rasterized text and only update the compositor matrix.
    final content = RepaintBoundary(
      child: MediaQuery.withNoTextScaling(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: enableEditing,
              child: textWidget,
            ),
          ],
        ),
      ),
    );

    return ValueListenableBuilder<Matrix4>(
      valueListenable: _transform,
      child: content,
      builder: (context, transform, child) => Transform(
        origin: const Offset(0, 0),
        transform: transform,
        child: child,
      ),
    );
  }

  void update(Matrix4 matrix) {
    // The editor can keep pushing transform updates to a layer that is not
    // mounted (or is already disposed), and such a state cannot rebuild.
    if (!mounted) return;
    widget.text.transform = matrix;
    _transform.value = matrix;
  }

  void disableEditing() {
    Navigator.of(context).popUntil((route) => route.settings.name == EditPage.routeName);
  }
}

class FontPreview extends StatelessWidget {
  final FontsRegistryEntry font;
  final bool active;

  const FontPreview(this.font, {super.key, this.active = false});

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.of(context).textScaler;
    final theme = Theme.of(context);
    final double paddingDiff = textScaler.scale(max(15 * (font.sizeMultiplier - 1), 0)) / 2;
    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(12, 8 - paddingDiff, 12, 8 - paddingDiff),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active
                ? theme.colorScheme.primary.withAlpha(theme.brightness == Brightness.light ? 100 : 50)
                : Colors.transparent,
          ),
          child: Baseline(
              baseline: textScaler.scale(15),
              baselineType: TextBaseline.alphabetic,
              child: Text(
                font.display ?? font.family,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                    color: Colors.white,
                    fontFamily: font.family,
                    fontSize: textScaler.scale(15 * font.sizeMultiplier)),
              )),
        ),
      ],
    );
  }
}
