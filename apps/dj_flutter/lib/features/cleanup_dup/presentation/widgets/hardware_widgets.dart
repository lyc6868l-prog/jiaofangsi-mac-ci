import 'dart:typed_data';
import 'dart:ui';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide BoxDecoration, BoxShadow;
import 'package:flutter_inset_box_shadow/flutter_inset_box_shadow.dart';
import 'package:dj_flutter/shared/hardware_ui/hardware_ui.dart' as shared;

import '../models/cleanup_dup_models.dart';

const Color kDeepBlack = shared.kDeepBlack;
const Color kPanelBg = shared.kPanelBg;
const Color kHardwareBlack = shared.kHardwareBlack;
const Color kTextGray = shared.kTextGray;
const Color kTextLightGray = shared.kTextLightGray;
const Color kCrimson = shared.kCrimson;
const Color kEmerald = shared.kEmerald;
const Color kAmber = shared.kAmber;

class CleanupDupGridBackground extends StatelessWidget {
  const CleanupDupGridBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return shared.HardwareGridBackground(child: child);
  }
}

class HardwarePanel extends StatelessWidget {
  const HardwarePanel({super.key, required this.child, this.watermark = '雷'});

  final Widget child;
  final String watermark;

  @override
  Widget build(BuildContext context) {
    return shared.HardwarePanel(watermark: watermark, child: child);
  }
}

class LcdStatusStrip extends StatelessWidget {
  const LcdStatusStrip({
    super.key,
    required this.statusText,
    required this.statusColor,
    this.items = const <Widget>[],
  });

  final String statusText;
  final Color statusColor;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return shared.HardwareLcdStatusStrip(
      items: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.8),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: statusColor,
              ),
            ),
          ],
        ),
        for (final Widget item in items) ...<Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: 1,
              height: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white10),
              ),
            ),
          ),
          item,
        ],
      ],
    );
  }
}

class HardwareInput extends StatelessWidget {
  const HardwareInput({
    super.key,
    this.controller,
    required this.placeholder,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final String placeholder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return shared.HardwareInput(
      controller: controller,
      placeholder: placeholder,
      enabled: enabled,
      useFocusGlow: true,
      accentColor: kCrimson,
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
    return shared.HardwareSelect(
      value: value,
      options: options,
      enabled: enabled,
      onChanged: onChanged,
    );
  }
}

class HardwareDropZone extends StatefulWidget {
  const HardwareDropZone({
    super.key,
    required this.hasFiles,
    required this.isDragging,
    required this.files,
    required this.hintText,
    this.onEmptyTap,
    this.onSelectFiles,
    this.onSelectFolder,
    this.onRemoveFile,
    this.onAppendTap,
    required this.onDragChanged,
    required this.onFilesDropped,
  });

  final bool hasFiles;
  final bool isDragging;
  final List<FileItem> files;
  final String hintText;
  final VoidCallback? onEmptyTap;
  final VoidCallback? onSelectFiles;
  final VoidCallback? onSelectFolder;
  final void Function(String path)? onRemoveFile;
  final VoidCallback? onAppendTap;
  final ValueChanged<bool> onDragChanged;
  final ValueChanged<List<String>> onFilesDropped;

  @override
  State<HardwareDropZone> createState() => _HardwareDropZoneState();
}

class _HardwareDropZoneState extends State<HardwareDropZone> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
    if (action == 'files' && widget.onSelectFiles != null) {
      widget.onSelectFiles!();
    } else if (action == 'folder' && widget.onSelectFolder != null) {
      widget.onSelectFolder!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DropTarget(
        onDragEntered: (_) {
          if (!widget.hasFiles) {
            widget.onDragChanged(true);
          }
        },
        onDragExited: (_) => widget.onDragChanged(false),
        onDragDone: (DropDoneDetails details) async {
          widget.onDragChanged(false);
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
              if (allowed) {
                final String resolvedPath = file.path;
                if (resolvedPath.isNotEmpty) {
                  paths.add(resolvedPath);
                }
              }
            }
          }
          if (paths.isNotEmpty) {
            widget.onFilesDropped(paths);
          }
        },
        child: InkWell(
          onTap: widget.hasFiles
              ? null
              : () {
                  if (widget.onEmptyTap != null) {
                    widget.onEmptyTap!();
                    return;
                  }
                  _showSelectMenu(context);
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: double.infinity,
            decoration: BoxDecoration(
              color: widget.isDragging
                  ? kCrimson.withValues(alpha: 0.05)
                  : kHardwareBlack,
              borderRadius: BorderRadius.circular(8),
              border: widget.hasFiles
                  ? Border.all(color: Colors.black.withValues(alpha: 0.9))
                  : null,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.98),
                  offset: const Offset(0, 4),
                  blurRadius: 20,
                  inset: true,
                ),
                if (widget.isDragging)
                  BoxShadow(
                    color: kCrimson.withValues(alpha: 0.2),
                    blurRadius: 30,
                    inset: true,
                  ),
              ],
            ),
            child: CustomPaint(
              painter: widget.hasFiles
                  ? null
                  : _DashedDropZonePainter(
                      color: widget.isDragging
                          ? kCrimson.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.05),
                    ),
              child: widget.hasFiles
                  ? Theme(
                      data: ThemeData.dark().copyWith(
                        scrollbarTheme: ScrollbarThemeData(
                          thumbColor: WidgetStateProperty.all(
                            const Color(0xFF1E1E24),
                          ),
                          trackColor: WidgetStateProperty.all(kHardwareBlack),
                          thickness: WidgetStateProperty.all(8),
                          radius: const Radius.circular(4),
                        ),
                      ),
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _scrollController,
                          primary: false,
                          padding: const EdgeInsets.all(8),
                          itemCount: widget.files.length + 1,
                          itemBuilder: (BuildContext context, int index) {
                            if (index == widget.files.length) {
                              if (widget.onAppendTap == null) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: _AppendTargetButton(
                                  onTap: widget.onAppendTap!,
                                ),
                              );
                            }
                            final FileItem file = widget.files[index];
                            return _FileItemTile(
                              file: file,
                              onRemoveFile: widget.onRemoveFile,
                            );
                          },
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Opacity(
                          opacity: 0.5,
                          child: Text('🗂️', style: TextStyle(fontSize: 24)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.hintText,
                          style: const TextStyle(
                            color: Color(0xFF4B5563),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileItemTile extends StatelessWidget {
  const _FileItemTile({required this.file, this.onRemoveFile});

  final FileItem file;
  final void Function(String path)? onRemoveFile;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                const Color(0xFF1E1E23).withValues(alpha: 0.4),
                const Color(0xFF0F0F12).withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      file.name,
                      style: const TextStyle(
                        color: kTextLightGray,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onRemoveFile != null)
                    _RemoveFileButton(onTap: () => onRemoveFile!(file.path)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppendTargetButton extends StatefulWidget {
  const _AppendTargetButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AppendTargetButton> createState() => _AppendTargetButtonState();
}

class _AppendTargetButtonState extends State<_AppendTargetButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered
                ? kCrimson.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _hovered
                  ? kCrimson.withValues(alpha: 0.3)
                  : Colors.white12,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '+',
                style: TextStyle(
                  color: _hovered ? kCrimson : kTextGray,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '追加目标',
                style: TextStyle(
                  color: _hovered ? kCrimson : kTextGray,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoveFileButton extends StatefulWidget {
  const _RemoveFileButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_RemoveFileButton> createState() => _RemoveFileButtonState();
}

class _RemoveFileButtonState extends State<_RemoveFileButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: _hovered
                ? kCrimson.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            '×',
            style: TextStyle(
              color: _hovered ? kCrimson : kTextGray,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedDropZonePainter extends CustomPainter {
  const _DashedDropZonePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const double dash = 8;
    const double gap = 6;
    final Path path = Path()..addRRect(rrect);
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = distance + dash;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedDropZonePainter oldDelegate) {
    return oldDelegate.color != color;
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
    return shared.HardwareProgressBar(value: value, hintText: hintText);
  }
}

class HardwareGiantButton extends StatelessWidget {
  const HardwareGiantButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isStart = true,
    this.enabled = true,
    this.isReviewMode = false,
    this.flashSignal = false,
  });

  final String label;
  final bool isStart;
  final bool enabled;
  final bool isReviewMode;
  final bool flashSignal;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: shared.HardwareGiantButton(
        onPressed: enabled ? onPressed : null,
        label: label,
        variant: isReviewMode
            ? shared.HardwareGiantButtonVariant.review
            : isStart
            ? shared.HardwareGiantButtonVariant.start
            : shared.HardwareGiantButtonVariant.stop,
        flashSignal: flashSignal,
      ),
    );
  }
}
