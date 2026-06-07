import 'package:flutter/material.dart';
import '../lang/translations.dart';
import '../services/support_service.dart';
import 'support_ticket_screen.dart';

class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tickets = await SupportService.fetchTickets();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _openNewTicket() async {
    final subjectCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String category = 'general';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(t('new_support_ticket') ?? 'New Support Ticket'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: subjectCtrl,
                    decoration: InputDecoration(
                      labelText: t('subject') ?? 'Subject',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: InputDecoration(
                      labelText: t('category') ?? 'Category',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'general',
                        child: Text('General'),
                      ),
                      const DropdownMenuItem(
                        value: 'account',
                        child: Text('Account'),
                      ),
                      const DropdownMenuItem(
                        value: 'billing',
                        child: Text('Billing'),
                      ),
                      const DropdownMenuItem(
                        value: 'technical',
                        child: Text('Technical'),
                      ),
                      const DropdownMenuItem(
                        value: 'report',
                        child: Text('Report'),
                      ),
                      DropdownMenuItem(
                        value: 'review_removal',
                        child: Text(
                          t('review_removal_category') ?? 'Review removal',
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => category = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyCtrl,
                    minLines: 4,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: t('message') ?? 'Message',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('cancel') ?? 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('submit') ?? 'Submit'),
            ),
          ],
        ),
      ),
    );

    if (created != true) {
      subjectCtrl.dispose();
      bodyCtrl.dispose();
      return;
    }

    try {
      final result = await SupportService.createTicket(
        subject: subjectCtrl.text.trim(),
        body: bodyCtrl.text.trim(),
        category: category,
      );
      subjectCtrl.dispose();
      bodyCtrl.dispose();
      if (!mounted) return;
      await _load();
      final ticket = result['ticket'] as Map<String, dynamic>?;
      if (ticket != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SupportTicketScreen(ticket: ticket),
          ),
        );
      }
    } catch (e) {
      subjectCtrl.dispose();
      bodyCtrl.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _confirmDeleteTicket(Map<String, dynamic> ticket) async {
    final id = (ticket['id'] as num?)?.toInt();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('delete') ?? 'Delete'),
        content: Text(
          t('delete_support_ticket_confirm') ??
              'Delete this support ticket and all messages?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel') ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('delete') ?? 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await SupportService.deleteTicket(id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'in_progress':
        return t('in_progress') ?? 'In progress';
      case 'closed':
        return t('closed') ?? 'Closed';
      default:
        return t('open') ?? 'Open';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('help_support') ?? 'Help & Support'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewTicket,
        icon: const Icon(Icons.add_comment_outlined),
        label: Text(t('new_ticket') ?? 'New Ticket'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _tickets.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.support_agent_outlined,
                      size: 56,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t('no_support_tickets') ?? 'No support tickets yet',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t('support_ticket_hint') ??
                          'Open a ticket and our team will reply from the admin dashboard.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: _tickets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final ticket = _tickets[i];
                  final unread = (ticket['unread_count'] as num?)?.toInt() ?? 0;
                  return Card(
                    child: ListTile(
                      onLongPress: () => _confirmDeleteTicket(ticket),
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.confirmation_number_outlined,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        ticket['subject']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        ticket['last_message']?.toString() ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (unread > 0)
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: theme.colorScheme.primary,
                              child: Text(
                                '$unread',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            Text(
                              _statusLabel(ticket['status']?.toString()),
                              style: theme.textTheme.labelSmall,
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: t('delete') ?? 'Delete',
                            onPressed: () => _confirmDeleteTicket(ticket),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SupportTicketScreen(ticket: ticket),
                          ),
                        ).then((_) => _load());
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
