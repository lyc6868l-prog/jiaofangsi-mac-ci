import 'package:flutter/material.dart';

class HistoryDropdown extends StatelessWidget {
  final List<Map<String, String>> items;
  final Function(String account, String password) onSelect;
  final Function(int index) onDelete;
  final double width;

  const HistoryDropdown({
    super.key,
    required this.items,
    required this.onSelect,
    required this.onDelete,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: _buildContainer(
        child: items.isEmpty
            ? Center(
                child: Text(
                  '暂无历史记录',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 13,
                  ),
                ),
              )
            : Column(
                children: items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return _HistoryItem(
                    account: item['account']!,
                    password: item['password']!,
                    onTap: () => onSelect(item['account']!, item['password']!),
                    onDelete: () => onDelete(index),
                  );
                }).toList(),
              ),
      ),
    );
  }

  Widget _buildContainer({required Widget child}) {
    return Container(
      width: width,
      constraints: BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: const Color(0xFF0d0d12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1a1a24), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.95),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
          BoxShadow(color: Colors.black, spreadRadius: 1),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 2, color: const Color(0xFFE11D48)),
            Expanded(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}

class _HistoryItem extends StatefulWidget {
  final String account;
  final String password;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryItem({
    required this.account,
    required this.password,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_HistoryItem> createState() => _HistoryItemState();
}

class _HistoryItemState extends State<_HistoryItem> {
  bool _isHovered = false;
  bool _isDeleteHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: _isHovered ? 20 : 16,
            vertical: 12,
          ),
          color: _isHovered ? const Color(0xFF1a1a24) : Colors.transparent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.account,
                  style: TextStyle(
                    color: _isHovered ? Colors.white : const Color(0xFFD1D5DB),
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MouseRegion(
                onEnter: (_) => setState(() => _isDeleteHovered = true),
                onExit: (_) => setState(() => _isDeleteHovered = false),
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onDelete,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 200),
                    scale: _isDeleteHovered ? 1.05 : 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(left: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isDeleteHovered
                            ? const Color(0xFFE11D48).withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _isDeleteHovered
                              ? const Color(0xFFE11D48).withValues(alpha: 0.4)
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        '删除',
                        style: TextStyle(
                          color: _isDeleteHovered
                              ? const Color(0xFFF43F5E)
                              : const Color(0xFF6B7280),
                          fontSize: 12,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
