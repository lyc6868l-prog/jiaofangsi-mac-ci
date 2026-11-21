import 'dart:ui';

import 'package:dj_flutter/shared/hardware_ui/hardware_ui.dart'
    show HardwareCheckboxIndicator;
import 'package:flutter/material.dart';

import '../controllers/cleanup_dup_controller.dart';
import '../models/cleanup_dup_models.dart';
import 'hardware_widgets.dart';

class DuplicateReviewModal extends StatelessWidget {
  const DuplicateReviewModal({super.key, required this.controller});

  final CleanupDupController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.showReviewModal) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: 1,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(color: Colors.black.withValues(alpha: 0.85)),
            ),
          ),
          Center(
            child: AnimatedScale(
              duration: const Duration(milliseconds: 400),
              scale: controller.showReviewModal ? 1 : 0.95,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                height: MediaQuery.of(context).size.height * 0.85,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      const Color(0xFF141418).withValues(alpha: 0.95),
                      const Color(0xFF0A0A0C).withValues(alpha: 0.98),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.9),
                      blurRadius: 60,
                      offset: const Offset(0, 30),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: <Widget>[
                    Positioned(
                      top: 0,
                      left: 1,
                      right: 1,
                      child: Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    Column(
                      children: <Widget>[
                        _ModalHeader(controller: controller),
                        Expanded(child: _ModalBody(controller: controller)),
                        _ModalFooter(controller: controller),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({required this.controller});

  final CleanupDupController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                const Flexible(
                  child: Text(
                    '🔍 查重结果全屏审阅',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFFF3F4F6),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: kCrimson.withValues(alpha: 0.2),
                    border: Border.all(color: kCrimson.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '共发现 ${controller.duplicateGroups.length} 组重复',
                    style: const TextStyle(color: kCrimson, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          _CloseTextButton(onPressed: controller.closeReviewModal),
        ],
      ),
    );
  }
}

class _ModalBody extends StatelessWidget {
  const _ModalBody({required this.controller});

  final CleanupDupController controller;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: controller.duplicateGroups.length,
      itemBuilder: (BuildContext context, int groupIndex) {
        final DuplicateGroup group = controller.duplicateGroups[groupIndex];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF050506),
            border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.02),
                    ),
                  ),
                ),
                child: Text(
                  '#${groupIndex + 1}: ${group.groupName}',
                  style: const TextStyle(
                    color: kTextLightGray,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...group.entries.asMap().entries.map((
                MapEntry<int, DuplicateEntry> pair,
              ) {
                final int entryIndex = pair.key;
                final DuplicateEntry entry = pair.value;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.02),
                      ),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      GestureDetector(
                        onTap: entry.isAutoKeep
                            ? null
                            : () => controller.toggleEntrySelection(
                                groupIndex,
                                entryIndex,
                              ),
                        behavior: HitTestBehavior.opaque,
                        child: HardwareCheckboxIndicator(
                          value: entry.isAutoKeep
                              ? false
                              : entry.isSelectedToDelete,
                          size: 14,
                          radius: 3,
                          disabled: entry.isAutoKeep,
                          uncheckedFillColor: Colors.transparent,
                          checkedFillColor: kCrimson.withValues(alpha: 0.16),
                          checkedBorderColor: kCrimson.withValues(alpha: 0.7),
                          uncheckedBorderColor: Colors.white24,
                          checkColor: kCrimson,
                          checkSize: 10,
                          borderWidth: 1,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '${entry.file.name} | ${entry.file.size}',
                          style: const TextStyle(
                            color: Color(0xFFF3F4F6),
                            fontSize: 13,
                            height: 1.35,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (entry.isAutoKeep)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: kEmerald.withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '自动保留',
                            style: TextStyle(color: kEmerald, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _ModalFooter extends StatelessWidget {
  const _ModalFooter({required this.controller});

  final CleanupDupController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          _CancelButton(onPressed: controller.closeReviewModal),
          const SizedBox(width: 16),
          _ExecuteButton(
            label: controller.isExecutingDelete
                ? '处理中...'
                : '💣 确认并删除已选 (${controller.selectedDeleteCount}项)',
            onPressed: () =>
                controller.onExecuteDelete(controller.selectedDeleteFiles()),
          ),
        ],
      ),
    );
  }
}

class _CloseTextButton extends StatefulWidget {
  const _CloseTextButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_CloseTextButton> createState() => _CloseTextButtonState();
}

class _CloseTextButtonState extends State<_CloseTextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Text(
          '×',
          style: TextStyle(
            color: _hovered ? const Color(0xFFF3F4F6) : kTextGray,
            fontSize: 24,
          ),
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: const Text(
          '取消并返回',
          style: TextStyle(
            color: kTextLightGray,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ExecuteButton extends StatefulWidget {
  const _ExecuteButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_ExecuteButton> createState() => _ExecuteButtonState();
}

class _ExecuteButtonState extends State<_ExecuteButton> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFE11D48), Color(0xFF9F1239)],
            ),
            border: Border.all(color: Colors.black.withValues(alpha: 0.9)),
            borderRadius: BorderRadius.circular(6),
            boxShadow: <BoxShadow>[
              if (!_pressed)
                BoxShadow(
                  color: Colors.black.withValues(alpha: _hovered ? 0.8 : 0.6),
                  blurRadius: _hovered ? 20 : 16,
                  offset: const Offset(0, 8),
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
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
