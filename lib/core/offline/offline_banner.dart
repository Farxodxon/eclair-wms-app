import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wms_app/core/offline/offline_controller.dart';

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(offlineControllerProvider);
    final count = state.pending;
    Widget? bar;

    if (state.needLogin) {
      bar = _BannerBar(
        color: Colors.orange.shade800,
        text: "Sessiya tugagan. Qayta kiring, saqlangan $count ta amal "
            "yo'qolmaydi.",
      );
    } else if (!state.online &&
        state.offlineSince != null &&
        DateTime.now().difference(state.offlineSince!) >=
            const Duration(minutes: 3)) {
      bar = _BannerBar(
        color: Colors.red.shade700,
        text: count > 0
            ? "Internet uzoq vaqt yo'q. Iltimos, signal yaxshi joyga chiqing. "
                "Saqlangan $count ta amal internet kelishi bilan o'zi "
                "avtomatik yuboriladi, qo'lda hech narsa qilish shart emas."
            : "Internet uzoq vaqt yo'q. Signal yaxshi joyga chiqing. "
                "Amallar saqlab boriladi va internet kelganda avtomatik "
                "yuboriladi.",
      );
    } else if (!state.online) {
      bar = _BannerBar(
        color: Colors.orange.shade800,
        text: "Internet yo'q. Amallar telefon/kompyuterda saqlanadi va "
            "internet kelganda avtomatik yuboriladi."
            "${count > 0 ? ' Saqlangan: $count ta' : ''}",
      );
    } else if (state.syncing || state.pending > 0) {
      bar = _BannerBar(
        color: Colors.blue.shade700,
        text: 'Yuborilmoqda: $count ta amal...',
      );
    } else if (state.failed > 0) {
      bar = _BannerBar(
        color: Colors.orange.shade800,
        text: "${state.failed} ta amal yuborilmadi. Ko'rish uchun bosing.",
      );
    }

    if (bar == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _showQueue(context, ref),
      child: bar,
    );
  }

  void _showQueue(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (ctx, innerRef, _) {
            final state = innerRef.watch(offlineControllerProvider);
            return AlertDialog(
              title: const Text('Oflayn navbat'),
              content: SizedBox(
                width: double.maxFinite,
                child: state.ops.isEmpty
                    ? const Text("Navbat bo'sh")
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: state.ops.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final op = state.ops[index];
                          final canDelete = op.status == 'failed' ||
                              op.status == 'uncertain';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(op.label),
                            subtitle: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_statusLabel(op.status)),
                                if (op.error != null && op.error!.isNotEmpty)
                                  Text(
                                    op.error!,
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: canDelete
                                ? TextButton(
                                    onPressed: () => innerRef
                                        .read(offlineControllerProvider
                                            .notifier)
                                        .deleteOp(op.id),
                                    child: const Text("O'chirish"),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Yopish'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'failed':
        return 'yuborilmadi';
      case 'uncertain':
        return 'noaniq';
      default:
        return 'kutmoqda';
    }
  }
}

class _BannerBar extends StatelessWidget {
  const _BannerBar({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SafeArea(
        bottom: false,
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}
