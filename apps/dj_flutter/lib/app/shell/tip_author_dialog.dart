import 'package:flutter/material.dart';

import 'dart:async';
import '../../shared/platform_utils.dart';
import 'shell_tokens.dart';
import 'tip_payment_service.dart';

/// 简化版打赏作者页面，视觉与用户中心深色面板保持一致。
Future<void> showTipAuthorDialog(
  BuildContext context, {
  String? donorName,
  required String token,
  required String authMode,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) =>
        _SimplifiedTipDialog(token: token, authMode: authMode),
  );
}

class _GiftItem {
  const _GiftItem({
    required this.title,
    required this.price,
    required this.icon,
    required this.tierId,
  });

  final String title;
  final int price;
  final IconData icon;
  final String tierId;
}

const List<_GiftItem> _gifts = <_GiftItem>[
  _GiftItem(title: '来瓶可乐', price: 3, icon: Icons.local_drink, tierId: 'cola'),
  _GiftItem(
    title: '来个鸡腿',
    price: 9,
    icon: Icons.lunch_dining,
    tierId: 'drumstick',
  ),
  _GiftItem(
    title: '来包华子',
    price: 60,
    icon: Icons.smoking_rooms,
    tierId: 'huazi',
  ),
  _GiftItem(
    title: '来包榔子',
    price: 100,
    icon: Icons.inventory_2_outlined,
    tierId: 'langzi',
  ),
];

class _RankItem {
  const _RankItem({
    required this.name,
    required this.amount,
    required this.hammerColor,
  });

  final String name;
  final String amount;
  final Color hammerColor;
}

const List<_RankItem> _ranks = <_RankItem>[
  _RankItem(
    name: 'NIGHTGHOST 夜鬼',
    amount: '¥200',
    hammerColor: Color(0xFFFBBF24),
  ),
  _RankItem(name: '日落之后', amount: '¥130', hammerColor: Color(0xFFD1D5DB)),
  _RankItem(name: 'DJ 随影', amount: '¥36', hammerColor: Color(0xFFB87333)),
  _RankItem(name: '虚位以待', amount: '', hammerColor: Color(0xFF9CA3AF)),
  _RankItem(name: '虚位以待', amount: '', hammerColor: Color(0xFF9A6B3F)),
];

class _SimplifiedTipDialog extends StatefulWidget {
  const _SimplifiedTipDialog({required this.token, required this.authMode});

  final String token;
  final String authMode;

  @override
  State<_SimplifiedTipDialog> createState() => _SimplifiedTipDialogState();
}

class _SimplifiedTipDialogState extends State<_SimplifiedTipDialog> {
  final TipPaymentService _service = TipPaymentService();
  int _selectedGift = 0;
  bool _paying = false;
  String? _error;
  final List<int> _quantities = List<int>.filled(_gifts.length, 1);
  List<_RankItem> _remoteRanks = const <_RankItem>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadLeaderboard());
  }

  Future<void> _loadLeaderboard() async {
    final List<Map<String, Object?>> rows = await _service.leaderboard(
      token: widget.token,
      authMode: widget.authMode,
    );
    if (!mounted || rows.isEmpty) return;
    final List<_RankItem> parsed = <_RankItem>[];
    for (int i = 0; i < rows.length && i < 3; i++) {
      final String name = (rows[i]['name'] ?? '乐工').toString();
      final double amount = (rows[i]['amount'] as num?)?.toDouble() ?? 0;
      parsed.add(
        _RankItem(
          name: name.isEmpty ? '乐工' : name,
          amount: '¥${amount.toStringAsFixed(0)}',
          hammerColor: <Color>[
            const Color(0xFFFBBF24),
            const Color(0xFFD1D5DB),
            const Color(0xFFB87333),
          ][i],
        ),
      );
    }
    if (mounted) setState(() => _remoteRanks = parsed);
  }

  List<_RankItem> get _displayRanks {
    final List<_RankItem> base = _remoteRanks.isNotEmpty
        ? _remoteRanks
        : _ranks.take(3).toList(growable: false);
    final List<_RankItem> result = <_RankItem>[...base.take(3)];
    while (result.length < 5) {
      result.add(
        _RankItem(
          name: '虚位以待',
          amount: '',
          hammerColor: result.length == 3
              ? const Color(0xFF9CA3AF)
              : const Color(0xFF9A6B3F),
        ),
      );
    }
    return result;
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _pay(_GiftItem gift) async {
    if (_paying) return;
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final TipPaymentOrder order = await _service.createOrder(
        token: widget.token,
        authMode: widget.authMode,
        tierId: gift.tierId,
        quantity: _quantities[_selectedGift],
      );
      await openUrl(order.paymentUrl);
      if (mounted) {
        setState(() => _error = '已打开支付宝付款页面');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: screen.height * 0.82,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[shellPanelTop, shellPanelBottom],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withValues(alpha: 0.9)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0xCC000000),
                blurRadius: 36,
                offset: Offset(0, 18),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _buildHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final bool wide = constraints.maxWidth > 560;
                          if (wide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(child: _buildGiftSection()),
                                const SizedBox(width: 16),
                                SizedBox(
                                  width: 300,
                                  child: _buildRankSection(),
                                ),
                              ],
                            );
                          }
                          return Column(
                            children: <Widget>[
                              _buildGiftSection(),
                              const SizedBox(height: 16),
                              _buildRankSection(),
                            ],
                          );
                        },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x1FFFFFFF)),
          top: BorderSide(color: shellAccentBlue, width: 2),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '打赏作者 · 教坊司功德录',
                  style: TextStyle(
                    color: shellTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '小小心意换一声“大哥大气”',
                  style: TextStyle(color: shellTextMuted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 17),
            color: shellTextMuted,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '礼物栏',
          style: TextStyle(
            color: shellTextSoft,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        if (_paying)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: shellAccentGold,
              backgroundColor: Color(0x22000000),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: shellTextMuted, fontSize: 10),
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _gifts.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 136,
          ),
          itemBuilder: (BuildContext context, int index) {
            return _buildGiftCard(_gifts[index], index);
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 36,
          child: FilledButton(
            onPressed: _paying ? null : _submitPayment,
            style: FilledButton.styleFrom(
              backgroundColor: shellAccentPinkDeep,
              foregroundColor: shellTextPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              _paying
                  ? '正在创建订单…'
                  : '确认支付 ¥${_gifts[_selectedGift].price * _quantities[_selectedGift]}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  void _changeQuantity(int index, int delta) {
    if (_paying) return;
    setState(() {
      _selectedGift = index;
      _quantities[index] = (_quantities[index] + delta).clamp(1, 99);
      _error = null;
    });
  }

  Future<void> _submitPayment() async {
    await _pay(_gifts[_selectedGift]);
  }

  Widget _buildGiftCard(_GiftItem gift, int index) {
    final bool selected = _selectedGift == index;
    return InkWell(
      onTap: _paying
          ? null
          : () {
              setState(() {
                _selectedGift = index;
                _error = null;
              });
            },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: selected
              ? shellAccentPinkDeep.withValues(alpha: 0.18)
              : shellPanelSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? shellAccentRed.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: shellPanelTop,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(gift.icon, size: 23, color: shellAccentGold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        gift.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? shellTextPrimary : shellTextSoft,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '¥${gift.price}',
                        style: const TextStyle(
                          color: shellAccentGold,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _QuantityButton(
                  icon: Icons.remove,
                  enabled: _quantities[index] > 1 && !_paying,
                  onTap: () => _changeQuantity(index, -1),
                ),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${_quantities[index]}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: shellTextPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _QuantityButton(
                  icon: Icons.add,
                  enabled: _quantities[index] < 99 && !_paying,
                  onTap: () => _changeQuantity(index, 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: shellPanelSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0xCC000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Text(
                '教坊司功德录',
                style: TextStyle(
                  color: shellTextSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              Spacer(),
              Text(
                '仅展示前五名',
                style: TextStyle(color: shellTextMuted, fontSize: 9.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._ranks
              .take(5)
              .toList()
              .asMap()
              .entries
              .map(
                (MapEntry<int, _RankItem> entry) =>
                    _buildRankRow(entry.key, entry.value),
              ),
        ],
      ),
    );
  }

  Widget _buildRankRow(int index, _RankItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Icon(Icons.gavel, size: 17, color: item.hammerColor),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: shellTextSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (item.amount.isNotEmpty)
            Text(
              item.amount,
              style: const TextStyle(
                color: shellAccentGold,
                fontSize: 10.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _QtyChip extends StatelessWidget {
  const _QtyChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? shellAccentPinkDeep.withValues(alpha: 0.2)
              : shellPanelSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? shellAccentRed.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? shellTextPrimary : shellTextMuted,
            fontSize: 10,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: shellPanelTop,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(
          icon,
          size: 13,
          color: enabled ? shellTextSoft : shellTextPlaceholder,
        ),
      ),
    );
  }
}
