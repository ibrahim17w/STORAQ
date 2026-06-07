import 'package:flutter/material.dart';
import '../lang/translations.dart';
import '../screens/support_ticket_screen.dart';
import '../services/support_service.dart';

Future<void> openPaymentConfirmationChat(
  BuildContext context, {
  required String referenceCode,
  required String paymentType,
  String? amountText,
}) async {
  final subject = '${t('payment_confirmation') ?? 'Payment confirmation'} - $referenceCode';
  final body = StringBuffer()
    ..writeln(
      '${t('payment_chat_intro') ?? 'I need help confirming my agent payment.'}',
    )
    ..writeln('${t('payment_type') ?? 'Payment type'}: $paymentType')
    ..writeln('${t('reference_code') ?? 'Reference code'}: $referenceCode');
  if (amountText != null && amountText.isNotEmpty) {
    body.writeln('${t('amount_due') ?? 'Amount due'}: $amountText');
  }

  try {
    final result = await SupportService.createTicket(
      subject: subject,
      body: body.toString().trim(),
      category: 'billing',
    );
    if (!context.mounted) return;
    final ticket = result['ticket'] as Map<String, dynamic>?;
    if (ticket == null) {
      throw Exception(t('failed') ?? 'Failed to open chat');
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupportTicketScreen(ticket: ticket),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}
