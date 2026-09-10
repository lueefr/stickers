import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/dialogs/eyedropper_dialog.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/pages/fonts_search_page.dart';
import 'package:stickers/src/widgets/text_layer.dart';

import '../pages/fonts_manager_page.dart';

class TextEditingDialog extends StatefulWidget {
  final Function disableEditing;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextLayer parent;

  final GestureTapCallback? onDelete;

  final GlobalKey rbKey;

  const TextEditingDialog({
    super.key,
    required this.disableEditing,
    required this.controller,
    required this.focusNode,
    required this.parent,
    this.onDelete,
    required this.rbKey,
  });

  @override
  State<TextEditingDialog> createState() => _TextEditingDialogState();
}

class _TextEditingDialogState extends State<TextEditingDialog> {
  int page = 0;

  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final fontCount = FontsRegistry.fontCount;
    // indexOf returns -1 when the layer font isn't in the registry.
    page = fontCount == 0 ? 0 : FontsRegistry.indexOf(widget.parent.text.fontName).clamp(0, fontCount - 1);
    _pageController = PageController(viewportFraction: .25, initialPage: page);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int _currentTool = 0;
  var _tools = <Widget>[];
  Color? _pickedColor;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: LayoutBuilder(builder: (context, constraints) {
        final isHorizontal = constraints.maxWidth > constraints.maxHeight;
        // The sticker text must not be distorted by the system font scaling,
        // otherwise the same sticker would look different on devices with
        // different accessibility settings.
        final editableTextStack = MediaQuery.withNoTextScaling(
          child: Stack(
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  widget.controller.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    inherit: false,
                    fontSize: widget.parent.text.fontSize *
                        (FontsRegistry.sizeMultiplier(widget.parent.text.fontName) ?? 1),
                    foreground: Paint()
                      ..strokeJoin = StrokeJoin.round
                      ..strokeCap = StrokeCap.round
                      ..color = widget.parent.text.outlineColor
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = widget.parent.text.outlineWidth,
                    fontFamily: widget.parent.text.fontName,
                  ),
                ),
            ]),
            EditableText(
              autofocus: true,
              onChanged: (_) {
                widget.parent.text.text = widget.controller.text;
                setState(() {});
              },
              onEditingComplete: () {
                widget.disableEditing();
              },
              maxLines: null,
              cursorOpacityAnimates: true,
              scrollPhysics: const NeverScrollableScrollPhysics(),
              controller: widget.controller,
              textAlign: TextAlign.center,
              focusNode: widget.focusNode,
              style: TextStyle(
                inherit: false,
                fontSize: widget.parent.text.fontSize *
                    (FontsRegistry.sizeMultiplier(widget.parent.text.fontName) ?? 1),
                color: widget.parent.text.textColor,
                fontFamily: widget.parent.text.fontName,
              ),
              cursorColor: widget.parent.text.textColor,
              backgroundCursorColor: widget.parent.text.textColor,
            ),
          ],
          ),
        );
        final decoratedTextField = widget.parent.data.backgroundColor == Colors.transparent
            ? editableTextStack
            : Container(
                padding: EdgeInsets.all(widget.parent.data.backgroundPadding),
                decoration: BoxDecoration(
                  color: widget.parent.data.backgroundColor,
                  borderRadius: BorderRadius.circular(widget.parent.data.backgroundRadius),
                ),
                child: editableTextStack,
              );
        // Own layer, so typing only repaints this area instead of re-running
        // the full-screen backdrop blur on every keystroke.
        final textField = RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(child: decoratedTextField),
          ),
        );
        final topActionBar = GestureDetector(
          onTap: () => widget.disableEditing(),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 12),
                child: IconButton(
                  tooltip: AppLocalizations.of(context)!.delete,
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDelete?.call();
                  },
                  icon: Icon(Icons.delete),
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, top: 8.0),
                    child: Text(
                      AppLocalizations.of(context)!.done,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).textScaler.scale(18),
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        final fontSelector = SizedBox(
          height: MediaQuery.of(context).textScaler.scale(15) + 24,
          child: PageView.builder(
            itemCount: FontsRegistry.fontCount + 1,
            onPageChanged: (page) {
              HapticFeedback.lightImpact();
              if (FontsRegistry.fontCount == 0) return;
              this.page = min(page, FontsRegistry.fontCount - 1);
              widget.parent.text.fontName = FontsRegistry.at(this.page).family;
              setState(() {});
            },
            pageSnapping: false,
            controller: _pageController,
            itemBuilder: (context, i) {
              if (i == FontsRegistry.fontCount) {
                return TextButton(
                    onPressed: () async {
                      final answer = settingsController.googleFonts ||
                          await showDialog(
                            context: context,
                            builder: (_) => GoogleFontsConfirmationDialog(),
                          );
                      if (!context.mounted) return;
                      if (answer != true) return;
                      Navigator.of(context)
                          .push(
                        MaterialPageRoute(
                          builder: (_) => FontsSearchPage(),
                        ),
                      )
                          .then((_) {
                        _pageController.animateToPage(
                          FontsRegistry.fontCount - 1,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.ease,
                        );
                      });
                    },
                    child: Text(AppLocalizations.of(context)!.moreFonts));
              }
              return GestureDetector(
                onTap: () {
                  _pageController.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeInOutQuad,
                  );
                },
                child: FontPreview(
                  FontsRegistry.at(i),
                  active: page == i,
                ),
              );
            },
          ),
        );
        final actions = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            LabeledIconButton(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                child: const Text(
                  "A",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontFamily: "Lobster",
                    color: Colors.white,
                  ),
                ),
              ),
              AppLocalizations.of(context)!.font,
              active: _currentTool == 0,
              onTap: () {
                _setTool(0);
              },
            ),
            LabeledIconButton(
              Padding(
                padding: const EdgeInsets.all(3.0),
                child: Icon(Icons.format_size, color: Colors.white),
              ),
              AppLocalizations.of(context)!.fontSize,
              active: _currentTool == 1,
              onTap: () {
                _setTool(1);
              },
            ),
            LabeledIconButton(
              Padding(
                padding: const EdgeInsets.all(3.0),
                child: Icon(Icons.palette, color: Colors.white),
              ),
              AppLocalizations.of(context)!.color,
              active: _currentTool == 2,
              onTap: () {
                _setTool(2);
              },
            ),
            LabeledIconButton(
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                child: Stack(
                  children: [
                    Text(
                      "A",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 3
                          ..color = Colors.white
                          ..strokeCap = StrokeCap.round
                          ..strokeJoin = StrokeJoin.round,
                      ),
                    ),
                    Text(
                      "A",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              AppLocalizations.of(context)!.outline,
              active: _currentTool == 3,
              onTap: () {
                _setTool(3);
              },
            ),
            LabeledIconButton(
              Padding(
                padding: const EdgeInsets.all(3.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 28,
                      height: 20,
                      decoration: BoxDecoration(
                        color: widget.parent.data.backgroundColor == Colors.transparent
                            ? Colors.white24
                            : widget.parent.data.backgroundColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white),
                      ),
                    ),
                    Text(
                      "A",
                      style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ],
                ),
              ),
              "Background",
              active: _currentTool == 4,
              onTap: () {
                _setTool(4);
              },
            ),
          ],
        );
        final fontSizeSlider = Slider(
          thumbColor: Colors.white,
          activeColor: Colors.white,
          min: 10,
          max: 120,
          value: widget.parent.text.fontSize,
          onChanged: (newSize) {
            if (newSize == 10 || newSize == 120) {
              HapticFeedback.lightImpact();
            }
            setState(() {
              widget.parent.text.fontSize = newSize;
            });
          },
        );
        final outlineWidthSlider = Row(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 4, 0),
              child: Row(
                children: [
                  widget.parent.text.outlineColor == Colors.transparent
                      ? FilledButton(
                          onPressed: () {},
                          child: Text(AppLocalizations.of(context)!.off),
                        )
                      : FilledButton.tonal(
                          onPressed: () {
                            setState(() {
                              // Intentionally bypassing _setOutlineColor
                              widget.parent.text.outlineColor = Colors.transparent;
                            });
                          },
                          child: Text(AppLocalizations.of(context)!.off),
                        ),
                ],
              ),
            ),
            Expanded(
              child: Slider(
                thumbColor: Colors.white,
                activeColor: Colors.white,
                min: 0,
                max: 50,
                value: widget.parent.text.outlineWidth,
                onChanged: (newWidth) {
                  if (newWidth == 0 || newWidth == 10) {
                    HapticFeedback.lightImpact();
                  }
                  setState(() {
                    widget.parent.text.outlineWidth = newWidth;
                  });
                },
              ),
            ),
          ],
        );
        final textColorPicker = Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: LayoutBuilder(builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: colors
                      .getRange(0, (colors.length / 2).floor())
                      .map((c) => ColorButton(
                            c,
                            size: constraints.maxWidth / 10 - 4,
                            onTap: () => _setTextColor(c),
                            active: c == widget.parent.text.textColor,
                          ))
                      .toList(),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: colors
                      .getRange((colors.length / 2).floor(), colors.length)
                      .map((c) => ColorButton(
                            size: constraints.maxWidth / 10 - 4,
                            c,
                            onTap: () => _setTextColor(c),
                            active: c == widget.parent.text.textColor,
                          ))
                      .toList(),
                ),
              ],
            );
          }),
        );
        final outlineColorPicker = Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: LayoutBuilder(builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: colors
                      .getRange(0, (colors.length / 2).floor())
                      .map((c) => ColorButton(
                            c,
                            size: constraints.maxWidth / 10 - 4,
                            onTap: () => _setOutlineColor(c),
                            active: c == widget.parent.text.outlineColor,
                          ))
                      .toList(),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: colors
                      .getRange((colors.length / 2).floor(), colors.length)
                      .map((c) => ColorButton(
                            size: constraints.maxWidth / 10 - 4,
                            c,
                            onTap: () => _setOutlineColor(c),
                            active: c == widget.parent.text.outlineColor,
                          ))
                      .toList(),
                ),
              ],
            );
          }),
        );

        final backgroundColorPicker = Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: LayoutBuilder(builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    widget.parent.data.backgroundColor == Colors.transparent
                        ? FilledButton(
                            onPressed: () {},
                            child: Text(AppLocalizations.of(context)!.off),
                          )
                        : FilledButton.tonal(
                            onPressed: () {
                              setState(() {
                                widget.parent.data.backgroundColor = Colors.transparent;
                              });
                            },
                            child: Text(AppLocalizations.of(context)!.off),
                          ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: colors
                      .getRange(0, (colors.length / 2).floor())
                      .map((c) => ColorButton(
                            c,
                            size: constraints.maxWidth / 10 - 4,
                            onTap: () => _setBackgroundColor(c),
                            active: c == widget.parent.data.backgroundColor,
                          ))
                      .toList(),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: colors
                      .getRange((colors.length / 2).floor(), colors.length)
                      .map((c) => ColorButton(
                            size: constraints.maxWidth / 10 - 4,
                            c,
                            onTap: () => _setBackgroundColor(c),
                            active: c == widget.parent.data.backgroundColor,
                          ))
                      .toList(),
                ),
                Row(
                  children: [
                    SizedBox(width: 16),
                    Text("Padding", style: TextStyle(color: Colors.white)),
                    Expanded(
                      child: Slider(
                        thumbColor: Colors.white,
                        activeColor: Colors.white,
                        min: 0,
                        max: 40,
                        value: widget.parent.data.backgroundPadding,
                        onChanged: (value) {
                          setState(() {
                            widget.parent.data.backgroundPadding = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    SizedBox(width: 16),
                    Text("Radius", style: TextStyle(color: Colors.white)),
                    Expanded(
                      child: Slider(
                        thumbColor: Colors.white,
                        activeColor: Colors.white,
                        min: 0,
                        max: 60,
                        value: widget.parent.data.backgroundRadius,
                        onChanged: (value) {
                          setState(() {
                            widget.parent.data.backgroundRadius = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
        );

        final outlineConfigurator = Column(
          children: [outlineColorPicker, outlineWidthSlider],
        );

        _tools = [fontSelector, fontSizeSlider, textColorPicker, outlineConfigurator, backgroundColorPicker];

        final toolbar = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 512),
                child: Column(
                  children: [
                    AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: KeyedSubtree(
                          key: ValueKey<int>(_currentTool),
                          child: _tools[_currentTool],
                        )),
                    actions,
                  ],
                ),
              ),
            ],
          ),
        );

        return isHorizontal
            ? SizedBox(
                child: Row(
                  children: [
                    Expanded(child: textField),
                    Expanded(
                        child: SingleChildScrollView(
                      child: Column(
                        children: [
                          topActionBar,
                          RepaintBoundary(child: toolbar),
                        ],
                      ),
                    ))
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  topActionBar,
                  Expanded(
                      child: SingleChildScrollView(
                    reverse: true,
                    child: textField,
                  )),
                  RepaintBoundary(child: toolbar),
                  const SizedBox(
                    height: 16,
                  )
                ],
              );
      }),
    );
  }

  void _setTool(int tool) {
    setState(() {
      _currentTool = tool;
    });
    HapticFeedback.lightImpact();
  }

  void _setTextColor(Color color) async {
    if (color == Colors.transparent) {
      _pickedColor = await showDialog(
          context: context,
          builder: (context) => EyedropperDialog(
              widget.rbKey.currentContext!.findRenderObject() as RenderRepaintBoundary));
      if (_pickedColor == null) return;
      color = _pickedColor!;
    }
    setState(() {
      widget.parent.text.textColor = color;
    });
  }

  void _setOutlineColor(Color color) async {
    if (color == Colors.transparent) {
      _pickedColor = await showDialog(
          context: context,
          builder: (context) => EyedropperDialog(
              widget.rbKey.currentContext!.findRenderObject() as RenderRepaintBoundary));
      if (_pickedColor == null) return;
      color = _pickedColor!;
    }
    setState(() {
      widget.parent.text.outlineColor = color;
    });
  }

  void _setBackgroundColor(Color color) async {
    if (color == Colors.transparent) {
      _pickedColor = await showDialog(
          context: context,
          builder: (context) => EyedropperDialog(
              widget.rbKey.currentContext!.findRenderObject() as RenderRepaintBoundary));
      if (_pickedColor == null) return;
      color = _pickedColor!;
    }
    setState(() {
      widget.parent.data.backgroundColor = color;
    });
  }
}

class LabeledIconButton extends StatelessWidget {
  final Widget icon;
  final String label;
  final bool active;

  final GestureTapCallback? onTap;

  const LabeledIconButton(this.icon, this.label, {super.key, this.active = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4.0).copyWith(bottom: 0, top: 8),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            // Matrix4.identity() * factor would also scale the w component,
            // which cancels the intended zoom after the perspective divide.
            transform: Matrix4.diagonal3Values(active ? 1.1 : 1.0, active ? 1.1 : 1.0, 1),
            transformAlignment: Alignment.center,
            curve: Curves.ease,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    transform: Matrix4.diagonal3Values(active ? 1.2 : 1.0, active ? 1.2 : 1.0, 1),
                    transformAlignment: Alignment.center,
                    curve: Curves.ease,
                    padding: EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      color: active ? Theme.of(context).colorScheme.primary.withAlpha(100) : null,
                    ),
                    child: icon),
                Padding(
                  padding: const EdgeInsets.all(8.0).copyWith(bottom: 0),
                  child: Text(
                    label,
                    style: TextStyle(color: Colors.white),
                  ),
                )
              ],
            ),
          ),
        ));
  }
}

class ColorButton extends StatelessWidget {
  final Color color;
  final GestureTapCallback? onTap;
  final bool active;

  final double? size;

  const ColorButton(
    this.color, {
    super.key,
    this.onTap,
    required this.active,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Container(
          height: size ?? 23,
          width: size ?? 23,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: color,
            border: Border.all(
              color: (active && color != Colors.transparent)
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 3,
            ),
          ),
          child: color == Colors.transparent ? Icon(Icons.colorize) : null,
        ),
      ),
    );
  }
}
