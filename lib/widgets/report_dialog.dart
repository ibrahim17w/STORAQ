import 'package:flutter/material.dart';
import '../lang/translations.dart';
import '../services/report_service.dart';
import 'guest_login_sheet.dart' as guest;

Future<bool> showContentReportDialog(
  BuildContext context, {
  required String targetType,
  required int targetId,
  int? storeId,
  required String title,
}) async {
  final canProceed = await guest.requireAuth(context);
  if (!canProceed || !context.mounted) return false;

  final reasonCtrl = TextEditingController();
  final submitted = await showDialog<String?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: reasonCtrl,
        maxLines: 4,
        maxLength: 2000,
        decoration: InputDecoration(
          hintText: t('report_reason_hint') ??
              'Describe the issue (at least 10 characters)',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t('cancel') ?? 'Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final reason = reasonCtrl.text.trim();
            if (reason.length < 10) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text(
                    t('report_reason_hint') ??
                        'Describe the issue (at least 10 characters)',
                  ),
                ),
              );
              return;
            }
            Navigator.pop(ctx, reason);
          },
          child: Text(t('submit_report') ?? 'Submit report'),
        ),
      ],
    ),
  );

  reasonCtrl.dispose();

  if (submitted == null || submitted.isEmpty || !context.mounted) {
    return false;
  }

  final reason = submitted;

  try {
    await ReportService.submit(
      targetType: targetType,
      targetId: targetId,
      storeId: storeId,
      reason: reason,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('report_submitted') ??
                'Report submitted. Our team will review it.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
    return false;
  }
}
