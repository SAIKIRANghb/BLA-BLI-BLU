import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';

/// `−  n  +` control used in cart lines and on the product page.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 10,
    this.compact = false,
    this.busy = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final bool compact;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 34.0 : 42.0;
    final canDec = value > min && !busy;
    final canInc = value < max && !busy;

    return Container(
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Btn(
            icon: Icons.remove_rounded,
            enabled: canDec,
            size: compact ? 18 : 20,
            onTap: () => onChanged(value - 1),
          ),
          SizedBox(
            width: compact ? 26 : 34,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: compact ? 13.5 : 15, fontWeight: FontWeight.w700),
            ),
          ),
          _Btn(
            icon: Icons.add_rounded,
            enabled: canInc,
            size: compact ? 18 : 20,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.enabled, required this.onTap, required this.size});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: size, color: enabled ? AppColors.ink : AppColors.muted.withValues(alpha: 0.4)),
      );
}
