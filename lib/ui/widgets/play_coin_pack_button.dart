import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/gem_label.dart';
import '../../services/coin_ledger.dart';
import '../theme/marge_theme.dart';

/// Play-money gem denominations. Not a cash purchase and not Play Billing.
class GemDenominationPicker extends StatefulWidget {
  const GemDenominationPicker({
    super.key,
    required this.onChosen,
    this.available,
    this.compact = false,
    this.title = 'Add gems',
    this.hint = 'Free gems. Not a real charge.',
  });

  /// Called with a denomination or a custom amount the player chose.
  final ValueChanged<int> onChosen;

  /// When set, this draws from the gem bank and cannot exceed [available].
  final int? available;

  final bool compact;
  final String title;
  final String hint;

  @override
  State<GemDenominationPicker> createState() => _GemDenominationPickerState();
}

class _GemDenominationPickerState extends State<GemDenominationPicker> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  bool _allowed(int gems) {
    if (gems <= 0) return false;
    final cap = widget.available;
    if (cap == null) return true;
    return gems <= cap;
  }

  void _submitCustom() {
    final gems = int.tryParse(_custom.text.trim());
    if (gems == null || !_allowed(gems)) return;
    widget.onChosen(gems);
    _custom.clear();
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MargeColors.gold,
            fontWeight: FontWeight.w800,
            fontSize: widget.compact ? 13 : 15,
          ),
        ),
        if (available != null) ...[
          const SizedBox(height: 2),
          Text(
            'Available ${gemCount(available)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MargeColors.cream.withValues(alpha: 0.8),
              fontSize: widget.compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final gems in PlayerCoinLedger.playGemDenominations)
              FilledButton(
                onPressed: _allowed(gems) ? () => widget.onChosen(gems) : null,
                child: Text(gemCount(gems)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _custom,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  isDense: true,
                  hintText: available == null
                      ? 'Custom amount'
                      : 'Up to ${gemCount(available)}',
                ),
                onSubmitted: (_) => _submitCustom(),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: _submitCustom, child: const Text('Use')),
          ],
        ),
        SizedBox(height: widget.compact ? 2 : 4),
        Text(
          widget.hint,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MargeColors.cream.withValues(alpha: 0.72),
            fontSize: widget.compact ? 11 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
