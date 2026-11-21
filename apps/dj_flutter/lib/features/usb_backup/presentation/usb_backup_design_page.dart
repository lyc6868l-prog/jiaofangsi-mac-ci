import 'package:flutter/material.dart';

class UsbBackupDesignPage extends StatelessWidget {
  const UsbBackupDesignPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 1200, minHeight: 480),
      decoration: const BoxDecoration(color: Color(0xFF030303)),
      child: Center(
        child: Container(
          width: 1360,
          height: 560,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1A1A1A)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF08080A), Color(0xFF000000)],
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    _Header(),
                    SizedBox(height: 12),
                    _DeviceRow(),
                    SizedBox(height: 12),
                    _ModeSwitch(),
                    SizedBox(height: 12),
                    Expanded(child: _BackupView()),
                    SizedBox(height: 12),
                    _Footer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          '💽 U 盘备份与恢复',
          style: TextStyle(
            color: Color(0xFFF3F4F6),
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF020202),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Color(0xFF1A1A1A)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '状态：',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                '待命',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 12),
              Text(
                '|',
                style: TextStyle(color: Color(0xFF333333), fontSize: 13),
              ),
              SizedBox(width: 12),
              Text(
                '检测到 U 盘：',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                '1',
                style: TextStyle(
                  color: Color(0xFFD1D5DB),
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF000000).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.02),
        ),
      ),
      child: const Row(
        children: [
          _UsbDropdown(),
          SizedBox(width: 12),
          Expanded(child: _CapacityBar()),
          SizedBox(width: 12),
          _ToolButton(text: '🔄 刷新'),
          SizedBox(width: 12),
          _ToolButton(text: '⏏ 弹出'),
          SizedBox(width: 12),
          _ToolButton(text: '格式化', isDanger: true),
        ],
      ),
    );
  }
}

class _UsbDropdown extends StatelessWidget {
  const _UsbDropdown();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 320),
      padding: EdgeInsets.symmetric(horizontal: 12),
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF020202),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.1),
        ),
      ),
      child: const Center(
        child: Text(
          '💾 [E:] PIONEER (FAT32) - 32GB',
          style: TextStyle(
            color: Color(0xFFD1D5DB),
            fontSize: 14,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

class _CapacityBar extends StatelessWidget {
  const _CapacityBar();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '已用：20.5 GB',
              style: TextStyle(
                color: const Color(0xFF9CA3AF),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              '剩余：11.5 GB',
              style: TextStyle(
                color: const Color(0xFF9CA3AF),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Container(
            height: 10,
            color: const Color(0xFF020202),
            child: FractionallySizedBox(
              widthFactor: 0.64,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF115E59), Color(0xFF10B981)],
                  ),
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  final String text;
  final bool isDanger;

  const _ToolButton({required this.text, this.isDanger = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E23).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDanger
              ? const Color(0xFFE11D48).withValues(alpha: 0.3)
              : const Color(0xFFFFFFFF).withValues(alpha: 0.1),
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: isDanger ? const Color(0xFFE11D48) : const Color(0xFFD1D5DB),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _ModeRadio(text: '一键 U 盘备份', isSelected: true),
          SizedBox(width: 40),
          _ModeRadio(text: '从备份恢复 U 盘', isSelected: false),
        ],
      ),
    );
  }
}

class _ModeRadio extends StatelessWidget {
  final String text;
  final bool isSelected;

  const _ModeRadio({required this.text, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF020202),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFE11D48)
                  : const Color(0xFF4B5563),
              width: 2,
            ),
          ),
          child: isSelected
              ? Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE11D48),
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : null,
        ),
        SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            color: isSelected
                ? const Color(0xFFE11D48)
                : const Color(0xFF6B7280),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _BackupView extends StatelessWidget {
  const _BackupView();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF000000).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.03),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _BackupActionBar(),
            SizedBox(height: 12),
            _ResumeCard(),
            SizedBox(height: 12),
            Expanded(child: _RekordboxSummaryCard()),
          ],
        ),
      ),
    );
  }
}

class _BackupActionBar extends StatelessWidget {
  const _BackupActionBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF020202),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.1),
              ),
            ),
            child: const Center(
              child: Text(
                'PIONEER_20260407',
                style: TextStyle(
                  color: Color(0xFFE5E7EB),
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        _ToolButton(text: '清理仓库'),
        SizedBox(width: 12),
        _ToolButton(text: '管理备份'),
      ],
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF020202),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '未完成备份检测',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  '可续传',
                  style: TextStyle(color: Color(0xFF10B981), fontSize: 11),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                color: Color(0xFFD1D5DB),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              children: [
                TextSpan(text: '检测到上次中断任务：'),
                TextSpan(
                  text: '主演出盘续传',
                  style: TextStyle(
                    color: Color(0xFFE11D48),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 4),
          const Text(
            '已完成 1200 / 3000 文件',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              height: 4,
              color: const Color(0xFF1E1E24),
              child: const FractionallySizedBox(
                widthFactor: 0.4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF4B5563),
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RekordboxSummaryCard extends StatelessWidget {
  const _RekordboxSummaryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF020202),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Rekordbox 摘要',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                '(就绪。目标设备校验完毕，符合备份标准)',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 11),
              ),
            ],
          ),
          SizedBox(height: 8),
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: const [
                _RbItem(
                  label: 'PIONEER 目录',
                  value: '存在',
                  valueColor: Color(0xFF10B981),
                ),
                _RbItem(
                  label: 'Contents 目录',
                  value: '存在',
                  valueColor: Color(0xFF10B981),
                ),
                _RbItem(
                  label: '核心数据库',
                  value: '1 个',
                  valueColor: Color(0xFF10B981),
                ),
                _RbItem(label: '音乐体积', value: '5.8 GB'),
                _RbItem(label: '音频解析', value: '128 首'),
                _RbItem(label: '波形/分析', value: '96 项'),
                _RbItem(label: '内置封面', value: '24 张'),
                _RbItem(
                  label: '.PIONEER',
                  value: '无',
                  valueColor: Color(0xFF6B7280),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RbItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _RbItem({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.02),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? const Color(0xFFD1D5DB),
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _StatText(label: '速度', value: '0 MB/s'),
                SizedBox(width: 24),
                _StatText(label: 'ETA', value: '--:--'),
              ],
            ),
            Row(
              children: [
                const Text(
                  'Rekordbox:',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  '未开始',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: 8),
        const _ProgressBar(),
        SizedBox(height: 12),
        const _ActionButtons(),
      ],
    );
  }
}

class _StatText extends StatelessWidget {
  final String label;
  final String value;

  const _StatText({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Color(0xFF9CA3AF),
          fontSize: 12,
          fontFamily: 'monospace',
        ),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Color(0xFFD1D5DB),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 10,
        color: const Color(0xFF020202),
        child: const FractionallySizedBox(
          widthFactor: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF4C0519),
                  Color(0xFFBE123C),
                  Color(0xFFFB7185),
                ],
              ),
              borderRadius: BorderRadius.horizontal(left: Radius.circular(5)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 3, child: _GiantButton(text: '一键开始备份')),
        SizedBox(width: 16),
        Expanded(flex: 1, child: _GiantButton(text: '紧急停止', isDanger: true)),
      ],
    );
  }
}

class _GiantButton extends StatelessWidget {
  final String text;
  final bool isDanger;

  const _GiantButton({required this.text, this.isDanger = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: isDanger
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1E0A0F), Color(0xFF0F0508)],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF28282D), Color(0xFF141418)],
              ),
        border: Border.all(
          color: isDanger
              ? const Color(0xFFE11D48).withValues(alpha: 0.3)
              : const Color(0xFF000000),
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: isDanger ? const Color(0xFFE11D48) : const Color(0xFFF3F4F6),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
