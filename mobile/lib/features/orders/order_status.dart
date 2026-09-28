import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';

/// Status vocabulary shared by the order list, detail and tracking screens.
abstract final class OrderStatus {
  static const stages = <String>['placed', 'confirmed', 'packed', 'shipped', 'delivered'];

  static String label(String status) {
    switch (status.toLowerCase()) {
      case 'placed':
        return 'Order placed';
      case 'confirmed':
        return 'Confirmed';
      case 'packed':
        return 'Packed';
      case 'shipped':
        return 'Shipped';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      case 'refunded':
        return 'Refunded';
      case 'returned':
        return 'Returned';
      default:
        return status.isEmpty ? 'Unknown' : status[0].toUpperCase() + status.substring(1);
    }
  }

  static Color color(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return AppColors.success;
      case 'shipped':
        return const Color(0xFF1B6FB5);
      case 'cancelled':
      case 'refunded':
      case 'returned':
        return AppColors.primary;
      default:
        return AppColors.star;
    }
  }

  static IconData icon(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return Icons.check_circle_rounded;
      case 'shipped':
        return Icons.local_shipping_rounded;
      case 'packed':
        return Icons.inventory_2_outlined;
      case 'confirmed':
        return Icons.verified_outlined;
      case 'cancelled':
      case 'refunded':
      case 'returned':
        return Icons.cancel_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  static bool isTerminal(String status) =>
      ['delivered', 'cancelled', 'refunded', 'returned'].contains(status.toLowerCase());
}

/// Pill used everywhere an order's state is shown.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.dense = false});

  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = OrderStatus.color(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(OrderStatus.icon(status), size: dense ? 12 : 14, color: color),
          const SizedBox(width: 5),
          Text(
            OrderStatus.label(status),
            style: TextStyle(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

/// Vertical stepper mirroring the storefront's tracking timeline.
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.order, this.compact = false});

  final Order order;
  final bool compact;

  int get _currentIndex {
    final idx = OrderStatus.stages.indexOf(order.status.toLowerCase());
    return idx < 0 ? -1 : idx;
  }

  OrderEvent? _eventFor(String stage) {
    for (final event in order.events.reversed) {
      if (event.status.toLowerCase() == stage) return event;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cancelled = ['cancelled', 'returned', 'refunded'].contains(order.status.toLowerCase());
    if (cancelled) {
      return _CancelledBanner(order: order);
    }

    final current = _currentIndex;
    final stages = compact ? OrderStatus.stages.take(4).toList() : OrderStatus.stages;

    return Column(
      children: [
        for (var i = 0; i < stages.length; i++)
          _Step(
            stage: stages[i],
            first: i == 0,
            last: i == stages.length - 1,
            done: i <= current,
            active: i == current,
            event: _eventFor(stages[i]),
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.stage,
    required this.first,
    required this.last,
    required this.done,
    required this.active,
    required this.event,
  });

  final String stage;
  final bool first;
  final bool last;
  final bool done;
  final bool active;
  final OrderEvent? event;

  @override
  Widget build(BuildContext context) {
    final color = done ? (active ? AppColors.star : AppColors.success) : AppColors.line;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                if (!first) Expanded(child: Container(width: 2, color: done ? color : AppColors.line)),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: done ? color : Colors.white, shape: BoxShape.circle, border: Border.all(color: done ? color : AppColors.line, width: 1.6)),
                  child: done
                      ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                      : const SizedBox(width: 7, height: 7, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.line, shape: BoxShape.circle))),
                ),
                if (!last) Expanded(child: Container(width: 2, color: done ? color : AppColors.line)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18, top: first ? 2 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    OrderStatus.label(stage),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                      color: done ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                  if (event != null && (event!.at.isNotEmpty || event!.note.isNotEmpty)) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (event!.at.isNotEmpty) _format(event!.at),
                        if (event!.note.isNotEmpty) event!.note,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _format(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final time = TimeOfDay.fromDateTime(parsed);
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    return '${parsed.day} ${months[parsed.month - 1]}, $hour:$minute ${time.period == DayPeriod.am ? 'AM' : 'PM'}';
  }
}

class _CancelledBanner extends StatelessWidget {
  const _CancelledBanner({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final color = OrderStatus.color(order.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(
        children: [
          Icon(OrderStatus.icon(order.status), color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(OrderStatus.label(order.status), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
                const SizedBox(height: 2),
                Text(
                  (order.events.isNotEmpty ? order.events.last.note : 'This order was ${OrderStatus.label(order.status).toLowerCase()}.'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
