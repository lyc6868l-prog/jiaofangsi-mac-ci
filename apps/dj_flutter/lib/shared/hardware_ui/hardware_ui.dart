import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide BoxDecoration, BoxShadow;
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart';

const kDeepBlack = Color(0xFF030303);
const kPanelBg = Color(0xFF08080A);
const kHardwareBlack = Color(0xFF020202);
const kTextGray = Color(0xFF9CA3AF);
const kTextLightGray = Color(0xFFD1D5DB);
const kCrimson = Color(0xFFE11D48);
const kEmerald = Color(0xFF10B981);
const kAmber = Color(0xFFD97706);

class HardwareCheckboxIndicator extends StatelessWidget {
  const HardwareCheckboxIndicator({
    super.key,
    required this.value,
    this.size = 16,
    this.radius = 3,
    this.isHovered = false,
    this.disabled = false,
    this.checkedFillColor = kCrimson,
    this.uncheckedFillColor = kHardwareBlack,
    this.checkedBorderColor = kCrimson,
    this.uncheckedBorderColor,
    this.hoverBorderColor,
    this.checkColor = Colors.white,
    this.checkSize,
    this.borderWidth = 1.2,
  });

  final bool value;
  final double size;
  final double radius;
  final bool isHovered;
  final bool disabled;
  final Color checkedFillColor;
  final Color uncheckedFillColor;
  final Color checkedBorderColor;
  final Color? uncheckedBorderColor;
  final Color? hoverBorderColor;
  final Color checkColor;
  final double? checkSize;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final Color resolvedUncheckedBorderColor =
        uncheckedBorderColor ?? Colors.white.withValues(alpha: 0.24);
    final Color resolvedHoverBorderColor =
        hoverBorderColor ?? Colors.white.withValues(alpha: 0.4);

    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: value ? checkedFillColor : uncheckedFillColor,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: value
                ? checkedBorderColor
                : (isHovered
                      ? resolvedHoverBorderColor
                      : resolvedUncheckedBorderColor),
            width: borderWidth,
          ),
        ),
        child: value
            ? Center(
                child: Icon(
                  Icons.check_rounded,
                  size: checkSize ?? (size - 4),
                  color: checkColor,
                ),
              )
            : null,
      ),
    );
  }
}

const double kHardwareDialogCompactWidth = 520;
const double kHardwareDialogStandardWidth = 560;
const double kHardwareDialogWideWidth = 760;
const double kHardwareDialogReviewWidth = 960;

class HardwareGridBackground extends StatelessWidget {
  const HardwareGridBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kDeepBlack,
      child: CustomPaint(painter: _GridBackgroundPainter(), child: child),
    );
  }
}

class _GridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.015)
      ..strokeWidth = 1;
    const double gap = 32;
    for (double x = 0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HardwarePanel extends StatelessWidget {
  const HardwarePanel({
    super.key,
    required this.child,
    this.watermark = '雷',
    this.headerTitle,
    this.headerAction,
  });

  final Widget child;
  final String watermark;
  final String? headerTitle;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kPanelBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.8)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.95),
            offset: const Offset(0, 4),
            blurRadius: 20,
            inset: true,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 10,
            inset: true,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.03),
            offset: const Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Center(
            child: Text(
              watermark,
              style: TextStyle(
                fontSize: 180,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.015),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (headerTitle != null) ...<Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        headerTitle!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: kTextLightGray,
                          letterSpacing: 1,
                        ),
                      ),
                      headerAction ?? const SizedBox.shrink(),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HardwareLcdStatusStrip extends StatelessWidget {
  const HardwareLcdStatusStrip({super.key, required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: kHardwareBlack,
        borderRadius: BorderRadius.circular(6),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 1),
            offset: const Offset(0, 2),
            blurRadius: 10,
            inset: true,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.03),
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(children: items),
    );
  }
}

class HardwareLcdItem extends StatelessWidget {
  const HardwareLcdItem({
    super.key,
    this.leading,
    required this.label,
    this.value,
    this.valueColor,
  });

  final Widget? leading;
  final String label;
  final String? value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (leading != null) ...<Widget>[leading!, const SizedBox(width: 8)],
        Text(
          '$label:',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: kTextGray,
          ),
        ),
        if (value != null) ...<Widget>[
          const SizedBox(width: 4),
          Text(
            value!,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: valueColor ?? kTextLightGray,
            ),
          ),
        ],
      ],
    );
  }
}

class HardwareInput extends StatefulWidget {
  const HardwareInput({
    super.key,
    this.controller,
    this.labelText = '',
    this.placeholder = '',
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
    this.onChanged,
    this.useFocusGlow = false,
    this.accentColor = kCrimson,
  });

  final TextEditingController? controller;
  final String labelText;
  final String placeholder;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final bool useFocusGlow;
  final Color accentColor;

  @override
  State<HardwareInput> createState() => _HardwareInputState();
}

class _HardwareInputState extends State<HardwareInput> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()
      ..addListener(() {
        if (!widget.useFocusGlow) {
          return;
        }
        setState(() => _focused = _focusNode.hasFocus);
      });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget textField = TextField(
      focusNode: _focusNode,
      controller: widget.controller,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
      enableSuggestions: false,
      autocorrect: false,
      onChanged: widget.onChanged,
      style: TextStyle(
        fontSize: 13,
        color: widget.enabled
            ? kTextLightGray
            : Colors.white.withValues(alpha: 0.45),
      ),
      decoration: InputDecoration(
        hintText: widget.placeholder,
        hintStyle: TextStyle(
          fontSize: 13,
          color: widget.useFocusGlow
              ? Colors.white.withValues(alpha: 0.2)
              : kTextGray,
        ),
        border: InputBorder.none,
        contentPadding: widget.labelText.isEmpty
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : EdgeInsets.zero,
        isDense: true,
      ),
    );

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 36,
        padding: widget.labelText.isEmpty
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: kHardwareBlack,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: widget.useFocusGlow && _focused
                ? widget.accentColor.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.03),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.9),
              offset: const Offset(0, 2),
              blurRadius: 10,
              inset: true,
            ),
            if (widget.useFocusGlow && _focused)
              BoxShadow(
                color: widget.accentColor.withValues(alpha: 0.1),
                blurRadius: 10,
              ),
          ],
        ),
        child: widget.labelText.isEmpty
            ? textField
            : Row(
                children: <Widget>[
                  Text(
                    widget.labelText,
                    style: const TextStyle(fontSize: 13, color: kTextGray),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IgnorePointer(
                      ignoring: widget.readOnly,
                      child: textField,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class HardwareSelect extends StatelessWidget {
  const HardwareSelect({
    super.key,
    required this.value,
    required this.options,
    this.enabled = true,
    this.onChanged,
  });

  final String value;
  final List<String> options;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: kHardwareBlack,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.9),
              offset: const Offset(0, 2),
              blurRadius: 10,
              inset: true,
            ),
          ],
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            dropdownColor: kHardwareBlack,
            icon: const Opacity(
              opacity: 0.5,
              child: Text(
                '▼',
                style: TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
            style: const TextStyle(color: kTextLightGray, fontSize: 13),
            items: options
                .map(
                  (String option) => DropdownMenuItem<String>(
                    value: option,
                    child: Text(option),
                  ),
                )
                .toList(),
            onChanged: enabled && onChanged != null
                ? (String? next) {
                    if (next != null) {
                      onChanged!(next);
                    }
                  }
                : null,
          ),
        ),
      ),
    );
  }
}

class HardwareConfirmButton extends StatelessWidget {
  const HardwareConfirmButton({
    super.key,
    this.onPressed,
    this.label = '确定',
    this.confirmed = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: confirmed ? null : onPressed,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF1E1E23), Color(0xFF0F0F12)],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black.withValues(alpha: 0.8)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              offset: const Offset(0, 4),
              blurRadius: 6,
            ),
          ],
        ),
        child: Center(
          child: Text(
            confirmed ? '已锁定' : label,
            style: TextStyle(
              fontSize: 13,
              color: confirmed ? Colors.white38 : kTextLightGray,
            ),
          ),
        ),
      ),
    );
  }
}

class HardwareDropZone extends StatelessWidget {
  const HardwareDropZone({
    super.key,
    required this.files,
    this.onFilesSelected,
    this.onSelectFolder,
    this.hintText = '点击选择或拖入文件/文件夹',
  });

  final List<String> files;
  final ValueChanged<List<String>>? onFilesSelected;
  final Future<void> Function()? onSelectFolder;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return _SharedHardwareDropZone(
      files: files,
      onFilesSelected: onFilesSelected,
      onSelectFolder: onSelectFolder,
      hintText: hintText,
    );
  }
}

class _SharedHardwareDropZone extends StatefulWidget {
  const _SharedHardwareDropZone({
    required this.files,
    this.onFilesSelected,
    this.onSelectFolder,
    required this.hintText,
  });

  final List<String> files;
  final ValueChanged<List<String>>? onFilesSelected;
  final Future<void> Function()? onSelectFolder;
  final String hintText;

  @override
  State<_SharedHardwareDropZone> createState() =>
      _SharedHardwareDropZoneState();
}

class _SharedHardwareDropZoneState extends State<_SharedHardwareDropZone> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final bool hasFiles = widget.files.isNotEmpty;
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (DropDoneDetails details) async {
        setState(() => _isDragging = false);
        if (hasFiles) {
          return;
        }
        final List<String> paths = <String>[];
        for (final XFile file in details.files) {
          if (file.path.isNotEmpty) {
            paths.add(file.path);
            continue;
          }
          final dynamic dropItem = file;
          final Object? bookmark = dropItem.extraAppleBookmark;
          if (bookmark is Uint8List) {
            final bool allowed = await DesktopDrop.instance
                .startAccessingSecurityScopedResource(bookmark: bookmark);
            if (allowed && file.path.isNotEmpty) {
              paths.add(file.path);
            }
          }
        }
        if (paths.isNotEmpty) {
          widget.onFilesSelected?.call(paths);
        }
      },
      child: GestureDetector(
        onTap: hasFiles ? null : () => _showSelectMenu(context),
        child: Container(
          decoration: BoxDecoration(
            color: kHardwareBlack,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isDragging
                  ? kCrimson.withValues(alpha: 0.8)
                  : hasFiles
                  ? Colors.black.withValues(alpha: 0.9)
                  : Colors.white.withValues(alpha: 0.05),
              width: hasFiles ? 1 : 2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.98),
                offset: const Offset(0, 4),
                blurRadius: 20,
                inset: true,
              ),
              if (_isDragging)
                BoxShadow(
                  color: kCrimson.withValues(alpha: 0.2),
                  blurRadius: 30,
                  inset: true,
                ),
            ],
          ),
          child: hasFiles ? _buildFileList() : _buildDropHint(),
        ),
      ),
    );
  }

  Widget _buildDropHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('🗂️', style: TextStyle(fontSize: 24, color: kTextGray)),
          const SizedBox(height: 8),
          Text(
            widget.hintText,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: kTextGray,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: widget.files.length,
      itemBuilder: (BuildContext context, int index) {
        final String fileName = widget.files[index].split('/').last;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[Color(0xFF1E1E23), Color(0xFF0F0F12)],
            ),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
          ),
          child: Text(
            fileName,
            style: const TextStyle(
              fontSize: 12,
              color: kTextLightGray,
              fontFamily: 'monospace',
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSelectMenu(BuildContext context) async {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final Offset center =
        box?.localToGlobal(box.size.center(Offset.zero)) ?? Offset.zero;
    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        center.dx,
        center.dy,
        center.dx,
        center.dy,
      ),
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'files', child: Text('选择音频文件')),
        PopupMenuItem<String>(value: 'folder', child: Text('选择文件夹')),
      ],
    );
    if (action == 'files') {
      await _openFilePicker();
    } else if (action == 'folder') {
      await widget.onSelectFolder?.call();
    }
  }

  Future<void> _openFilePicker() async {
    final List<XFile> files = await openFiles(confirmButtonText: '导入');
    final List<String> paths = files
        .map((XFile file) => file.path)
        .where((String path) => path.isNotEmpty)
        .toList();
    if (paths.isNotEmpty) {
      widget.onFilesSelected?.call(paths);
    }
  }
}

class HardwareProgressBar extends StatelessWidget {
  const HardwareProgressBar({
    super.key,
    required this.value,
    required this.hintText,
  });

  final double value;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final double clamped = value.clamp(0, 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              hintText,
              style: const TextStyle(
                color: kTextGray,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              '${(clamped * 100).floor()}%',
              style: const TextStyle(
                color: kCrimson,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                fontFamily: 'monospace',
                shadows: <Shadow>[Shadow(color: kCrimson, blurRadius: 8)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 10,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: kHardwareBlack,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.black.withValues(alpha: 0.8)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.9),
                offset: const Offset(0, 2),
                blurRadius: 6,
                inset: true,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.05),
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: clamped,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: <Color>[
                          Color(0xFF4C0519),
                          Color(0xFFBE123C),
                          Color(0xFFFB7185),
                        ],
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(color: kCrimson, blurRadius: 15),
                      ],
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 15,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: <Color>[Colors.transparent, Colors.white],
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.8),
                              blurRadius: 15,
                              spreadRadius: 3,
                            ),
                            BoxShadow(
                              color: kCrimson.withValues(alpha: 0.8),
                              blurRadius: 25,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: IgnorePointer(child: _ProgressSegmentsLayer()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressSegmentsLayer extends StatelessWidget {
  const _ProgressSegmentsLayer();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ProgressSegmentsPainter());
  }
}

class _ProgressSegmentsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = Colors.black.withValues(alpha: 0.7);
    for (double x = 4; x < size.width; x += 6) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

enum HardwareGiantButtonVariant { start, stop, review }

class HardwareGiantButton extends StatefulWidget {
  const HardwareGiantButton({
    super.key,
    this.onPressed,
    required this.label,
    this.variant = HardwareGiantButtonVariant.start,
    this.flashSignal = false,
    this.keepFlashing = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final HardwareGiantButtonVariant variant;
  final bool flashSignal;
  final bool keepFlashing;

  @override
  State<HardwareGiantButton> createState() => _HardwareGiantButtonState();
}

enum HardwareDialogActionVariant { neutral, confirm, danger }

typedef HardwareDialogBodyBuilder =
    Widget Function(BuildContext context, ScrollController scrollController);

Future<T?> showHardwareDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = const Color(0xBF000000),
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final Completer<T?> completer = Completer<T?>();
  final NavigatorState hostNavigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  );
  final OverlayState overlayState = hostNavigator.overlay!;
  final GlobalKey<NavigatorState> dialogNavigatorKey =
      GlobalKey<NavigatorState>();

  late final OverlayEntry overlayEntry;
  void dismiss([T? result]) {
    if (!completer.isCompleted) {
      completer.complete(result);
    }
    overlayEntry.remove();
  }

  final _HardwareDialogRoute<T> dialogRoute = _HardwareDialogRoute<T>(
    builder: builder,
    settings: routeSettings,
    onComplete: dismiss,
  );

  overlayEntry = OverlayEntry(
    builder: (BuildContext overlayContext) {
      return Positioned.fill(
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: barrierDismissible
                      ? () {
                          final NavigatorState? navigator =
                              dialogNavigatorKey.currentState;
                          if (navigator != null && navigator.canPop()) {
                            navigator.pop();
                          } else {
                            dismiss();
                          }
                        }
                      : null,
                  child: ColoredBox(color: barrierColor),
                ),
              ),
              Positioned.fill(
                child: Navigator(
                  key: dialogNavigatorKey,
                  onGenerateInitialRoutes:
                      (NavigatorState navigator, String initialRoute) {
                        return <Route<dynamic>>[dialogRoute];
                      },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  overlayState.insert(overlayEntry);
  return completer.future;
}

class _HardwareDialogRoute<T> extends PageRoute<T> {
  _HardwareDialogRoute({
    required this.builder,
    required this.onComplete,
    super.settings,
  });

  final WidgetBuilder builder;
  final ValueChanged<T?> onComplete;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }

  @override
  void didComplete(T? result) {
    onComplete(result);
    super.didComplete(result);
  }
}

Future<void> showHardwareMessageDialog({
  required BuildContext context,
  required String title,
  required String message,
  Widget? titleIcon,
  String actionLabel = '知道了',
  String hudTitle = 'System Notice / 提示',
  HardwareDialogActionVariant actionVariant =
      HardwareDialogActionVariant.confirm,
  bool barrierDismissible = true,
}) {
  return showHardwareDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext dialogContext) {
      return HardwareDialog(
        title: title,
        titleIcon: titleIcon ?? const Icon(Icons.info_outline_rounded),
        onClose: () => Navigator.of(dialogContext).pop(),
        hudTitle: hudTitle,
        hudText: Text(message, style: const TextStyle(height: 1.6)),
        body: const SizedBox.shrink(),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        footer: HardwareDialogFooter(
          actions: <Widget>[
            HardwareDialogAction(
              label: actionLabel,
              variant: actionVariant,
              expand: false,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      );
    },
  );
}

Future<bool> showHardwareConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelLabel = '取消',
  String confirmLabel = '确认',
  Widget? titleIcon,
  String hudTitle = 'System Warning / 注意事项',
  HardwareDialogActionVariant cancelVariant =
      HardwareDialogActionVariant.danger,
  HardwareDialogActionVariant confirmVariant =
      HardwareDialogActionVariant.confirm,
  bool barrierDismissible = true,
}) async {
  final bool? result = await showHardwareDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext dialogContext) {
      return HardwareDialog(
        title: title,
        titleIcon: titleIcon ?? const Icon(Icons.warning_amber_rounded),
        onClose: () => Navigator.of(dialogContext).pop(false),
        hudTitle: hudTitle,
        hudText: Text(message, style: const TextStyle(height: 1.6)),
        body: const SizedBox.shrink(),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        footer: HardwareDialogFooter(
          actions: <Widget>[
            HardwareDialogAction(
              label: cancelLabel,
              variant: cancelVariant,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            HardwareDialogAction(
              label: confirmLabel,
              variant: confirmVariant,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}

class HardwareDialogAction extends StatelessWidget {
  const HardwareDialogAction({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = HardwareDialogActionVariant.neutral,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final HardwareDialogActionVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Color accent = switch (variant) {
      HardwareDialogActionVariant.confirm => kEmerald,
      HardwareDialogActionVariant.danger => kCrimson,
      HardwareDialogActionVariant.neutral => kTextGray,
    };
    final bool enabled = onPressed != null;

    final Widget button = Opacity(
      opacity: enabled ? 1 : 0.38,
      child: _HardwareDialogActionButton(
        label: label,
        accent: accent,
        enabled: enabled,
        onPressed: onPressed,
      ),
    );

    if (expand) {
      return Expanded(child: button);
    }
    return button;
  }
}

class _HardwareDialogActionButton extends StatefulWidget {
  const _HardwareDialogActionButton({
    required this.label,
    required this.accent,
    required this.enabled,
    this.onPressed,
  });

  final String label;
  final Color accent;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  State<_HardwareDialogActionButton> createState() =>
      _HardwareDialogActionButtonState();
}

class _HardwareDialogActionButtonState
    extends State<_HardwareDialogActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool glow = _isHovered || _isPressed;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTapDown: widget.enabled
            ? (_) => setState(() => _isPressed = true)
            : null,
        onTapUp: widget.enabled
            ? (_) => setState(() => _isPressed = false)
            : null,
        onTapCancel: widget.enabled
            ? () => setState(() => _isPressed = false)
            : null,
        onTap: widget.enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 42,
          transform: Matrix4.translationValues(0, _isPressed ? 3 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                const Color(0xFF1E1E23).withValues(alpha: 0.6),
                const Color(0xFF0F0F12).withValues(alpha: 0.85),
              ],
            ),
            border: Border.all(color: Colors.black.withValues(alpha: 0.92)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: glow ? 0.82 : 0.62),
                offset: Offset(0, glow ? 8 : 4),
                blurRadius: glow ? 16 : 8,
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.05),
                offset: const Offset(0, 1),
                inset: true,
              ),
              if (_isPressed)
                BoxShadow(
                  color: widget.accent.withValues(alpha: 0.3),
                  blurRadius: 20,
                  inset: true,
                ),
              if (glow)
                BoxShadow(
                  color: widget.accent.withValues(alpha: 0.16),
                  blurRadius: 20,
                ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Positioned(
                top: 0,
                left: 1,
                right: 1,
                child: Container(
                  height: 1,
                  color: widget.accent.withValues(alpha: glow ? 0.6 : 0.22),
                ),
              ),
              Text(
                widget.label,
                style: TextStyle(
                  color: glow ? widget.accent : kTextLightGray,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  shadows: glow
                      ? <Shadow>[
                          Shadow(
                            color: widget.accent.withValues(alpha: 0.75),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HardwareDialog extends StatelessWidget {
  const HardwareDialog({
    super.key,
    required this.title,
    this.titleIcon,
    this.onClose,
    this.body,
    this.bodyBuilder,
    this.footer,
    this.width = 480,
    this.maxWidth,
    this.height,
    this.maxHeight,
    this.scrollable = false,
    this.hudTitle,
    this.hudText,
    this.hudAccent = kAmber,
    this.contentPadding = const EdgeInsets.all(24),
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 24,
      vertical: 24,
    ),
  }) : assert(body != null || bodyBuilder != null);

  final String title;
  final Widget? titleIcon;
  final VoidCallback? onClose;
  final Widget? body;
  final HardwareDialogBodyBuilder? bodyBuilder;
  final Widget? footer;
  final double width;
  final double? maxWidth;
  final double? height;
  final double? maxHeight;
  final bool scrollable;
  final String? hudTitle;
  final Widget? hudText;
  final Color hudAccent;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry insetPadding;

  @override
  Widget build(BuildContext context) {
    final ScrollController scrollController = ScrollController();
    final Widget contentBody = bodyBuilder != null
        ? Builder(
            builder: (BuildContext context) {
              return bodyBuilder!(context, scrollController);
            },
          )
        : body!;

    Widget bodySection = Padding(
      padding: contentPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (hudTitle != null || hudText != null) ...<Widget>[
            _HardwareDialogHudPanel(
              title: hudTitle,
              text: hudText,
              accent: hudAccent,
            ),
            const SizedBox(height: 20),
          ],
          if (scrollable)
            Expanded(
              child: Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: contentBody,
                ),
              ),
            )
          else
            contentBody,
        ],
      ),
    );

    Widget dialogChild = Container(
      width: width,
      constraints: BoxConstraints(
        maxWidth: maxWidth ?? width,
        maxHeight: maxHeight ?? MediaQuery.of(context).size.height * 0.9,
      ),
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            const Color(0xFF141418).withValues(alpha: 0.95),
            const Color(0xFF0A0A0C).withValues(alpha: 0.985),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.92),
            blurRadius: 60,
            offset: const Offset(0, 30),
          ),
          BoxShadow(color: kCrimson.withValues(alpha: 0.15), blurRadius: 40),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.05),
            offset: const Offset(0, 1),
            inset: true,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
        children: <Widget>[
          _HardwareDialogHeader(
            title: title,
            titleIcon: titleIcon,
            onClose: onClose,
          ),
          if (height != null || scrollable)
            Expanded(child: bodySection)
          else
            bodySection,
          if (footer case final Widget footerWidget) footerWidget,
        ],
      ),
    );

    return Padding(
      padding: insetPadding,
      child: Center(child: dialogChild),
    );
  }
}

class _HardwareDialogHeader extends StatelessWidget {
  const _HardwareDialogHeader({
    required this.title,
    this.titleIcon,
    this.onClose,
  });

  final String title;
  final Widget? titleIcon;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[kCrimson.withValues(alpha: 0.08), Colors.transparent],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                if (titleIcon != null) ...<Widget>[
                  DefaultTextStyle(
                    style: const TextStyle(fontSize: 18, color: kCrimson),
                    child: IconTheme(
                      data: const IconThemeData(color: kCrimson, size: 18),
                      child: titleIcon!,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF3F4F6),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null)
            _HardwareDialogCloseButton(onPressed: onClose!)
          else
            const SizedBox(width: 28),
        ],
      ),
    );
  }
}

class _HardwareDialogCloseButton extends StatefulWidget {
  const _HardwareDialogCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_HardwareDialogCloseButton> createState() =>
      _HardwareDialogCloseButtonState();
}

class _HardwareDialogCloseButtonState
    extends State<_HardwareDialogCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: _hovered ? const Color(0xFFF3F4F6) : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}

class _HardwareDialogHudPanel extends StatelessWidget {
  const _HardwareDialogHudPanel({this.title, this.text, required this.accent});

  final String? title;
  final Widget? text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kHardwareBlack,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.92),
            offset: const Offset(0, 4),
            blurRadius: 15,
            inset: true,
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (title != null && title!.isNotEmpty) ...<Widget>[
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 12,
                      color: accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                DefaultTextStyle(
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: kTextLightGray,
                    height: 1.6,
                  ),
                  child: text ?? const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HardwareDialogFooter extends StatelessWidget {
  const HardwareDialogFooter({
    super.key,
    required this.actions,
    this.padding = const EdgeInsets.fromLTRB(24, 16, 24, 16),
    this.alignment,
    this.gap = 16,
  });

  final List<Widget> actions;
  final EdgeInsetsGeometry padding;
  final MainAxisAlignment? alignment;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final List<Widget> effectiveActions = actions
        .where(
          (Widget action) =>
              action is! SizedBox || action.width != 0 || action.height != 0,
        )
        .toList(growable: false);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        mainAxisAlignment:
            alignment ??
            (effectiveActions.length <= 1
                ? MainAxisAlignment.end
                : MainAxisAlignment.start),
        children:
            effectiveActions
                .expand(
                  (Widget action) => <Widget>[action, SizedBox(width: gap)],
                )
                .toList()
              ..removeLast(),
      ),
    );
  }
}

class HardwareDialogSectionCard extends StatelessWidget {
  const HardwareDialogSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.borderColor,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? const Color(0xFF050506),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.04),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            offset: const Offset(0, 4),
            blurRadius: 10,
            inset: true,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HardwareGiantButtonState extends State<HardwareGiantButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isFlashing = false;
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    if (widget.keepFlashing) {
      _startPersistentFlash();
    }
  }

  @override
  void didUpdateWidget(covariant HardwareGiantButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flashSignal != widget.flashSignal && widget.flashSignal) {
      _triggerFlash();
    }
    if (!oldWidget.keepFlashing && widget.keepFlashing) {
      _startPersistentFlash();
    } else if (oldWidget.keepFlashing && !widget.keepFlashing) {
      _stopFlash();
    }
  }

  void _startPersistentFlash() {
    if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
    setState(() => _isFlashing = true);
  }

  void _stopFlash() {
    _controller.stop();
    _controller.value = 0;
    if (mounted) {
      setState(() => _isFlashing = false);
    }
  }

  void _triggerFlash() {
    _startPersistentFlash();
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted || widget.keepFlashing) {
        return;
      }
      _stopFlash();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        final bool enabled = widget.onPressed != null;
        final Color accent = widget.variant == HardwareGiantButtonVariant.stop
            ? kCrimson
            : kEmerald;
        final double flash = _isFlashing ? _controller.value : 0;
        final bool glowing =
            widget.variant == HardwareGiantButtonVariant.review ||
            _isHovered ||
            _isFlashing ||
            _isPressed;
        final double topLineAlpha =
            widget.variant == HardwareGiantButtonVariant.review
            ? 0.8
            : _isFlashing
            ? 0.2 + (flash * 0.8)
            : _isHovered || _isPressed
            ? 0.6
            : 0.2;
        List<BoxShadow>? innerShadows;

        if (widget.variant == HardwareGiantButtonVariant.review) {
          innerShadows = <BoxShadow>[
            BoxShadow(
              color: kEmerald.withValues(alpha: 0.2),
              blurRadius: 10,
              inset: true,
            ),
          ];
        }

        return Opacity(
          opacity: enabled ? 1 : 0.38,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTapDown: enabled
                  ? (_) => setState(() => _isPressed = true)
                  : null,
              onTapUp: enabled
                  ? (_) => setState(() => _isPressed = false)
                  : null,
              onTapCancel: enabled
                  ? () => setState(() => _isPressed = false)
                  : null,
              onTap: enabled ? widget.onPressed : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 40,
                transform: Matrix4.translationValues(0, _isPressed ? 3 : 0, 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: widget.variant == HardwareGiantButtonVariant.review
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            kEmerald.withValues(alpha: 0.2),
                            const Color(0xFF0F0F12).withValues(alpha: 0.9),
                          ],
                        )
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            const Color(0xFF1E1E23).withValues(alpha: 0.6),
                            const Color(0xFF0F0F12).withValues(alpha: 0.8),
                          ],
                        ),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.9),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _isHovered ? 0.8 : 0.6,
                      ),
                      offset: Offset(0, _isHovered ? 8 : 4),
                      blurRadius: _isHovered ? 16 : 8,
                    ),
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.05),
                      offset: const Offset(0, 1),
                      inset: true,
                    ),
                    if (_isPressed)
                      BoxShadow(
                        color: accent.withValues(
                          alpha:
                              widget.variant == HardwareGiantButtonVariant.stop
                              ? 0.35
                              : 0.4,
                        ),
                        blurRadius: 20,
                        inset: true,
                      ),
                    if (glowing)
                      BoxShadow(
                        color: accent.withValues(
                          alpha:
                              widget.variant ==
                                  HardwareGiantButtonVariant.review
                              ? 0.4
                              : (_isFlashing ? 0.4 * flash : 0.15),
                        ),
                        blurRadius:
                            widget.variant == HardwareGiantButtonVariant.review
                            ? 30
                            : 20,
                      ),
                    if (innerShadows != null) ...innerShadows,
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Positioned(
                      top: 0,
                      left: 1,
                      right: 1,
                      child: Container(
                        height: 1,
                        color: accent.withValues(alpha: topLineAlpha),
                      ),
                    ),
                    Text(
                      widget.label,
                      style: TextStyle(
                        color:
                            widget.variant == HardwareGiantButtonVariant.review
                            ? kEmerald
                            : widget.variant == HardwareGiantButtonVariant.stop
                            ? (_isHovered || _isPressed
                                  ? kCrimson
                                  : const Color(0xFF9CA3AF))
                            : (_isHovered || _isPressed || _isFlashing
                                  ? kEmerald
                                  : kTextLightGray),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1,
                        shadows: glowing
                            ? <Shadow>[
                                Shadow(
                                  color: accent.withValues(alpha: 0.8),
                                  blurRadius:
                                      widget.variant ==
                                          HardwareGiantButtonVariant.review
                                      ? 8
                                      : 12,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
