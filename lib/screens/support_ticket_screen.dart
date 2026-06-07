import 'dart:async';
import 'package:flutter/material.dart';
import '../lang/translations.dart';
import '../services/support_service.dart';

class SupportTicketScreen extends StatefulWidget {
  final Map<String, dynamic> ticket;

  const SupportTicketScreen({super.key, required this.ticket});

  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  Map<String, dynamic>? _ticket;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _pollTimer;

  int get _ticketId => (widget.ticket['id'] as num?)?.toInt() ?? 0;

  bool get _isClosed => _ticket?['status']?.toString() == 'closed';

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
    _load(silent: false);
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool silent}) async {
    if (_ticketId <= 0) return;
    if (!silent) setState(() => _loading = true);

    try {
      final data = await SupportService.fetchTicketThread(_ticketId);
      if (!mounted) return;
      setState(() {
        _ticket = data['ticket'] as Map<String, dynamic>? ?? _ticket;
        _messages = (data['messages'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        _loading = false;
      });
      if (_scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    } catch (_) {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _isClosed) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      final sent = await SupportService.sendReply(_ticketId, text);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, sent];
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subject = _ticket?['subject']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          if (_isClosed)
            Material(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t('ticket_closed') ??
                            'This ticket is closed. Open a new ticket if you need more help.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isAdmin = m['sender_role']?.toString() == 'admin';
                      return Align(
                        alignment: isAdmin
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                          ),
                          decoration: BoxDecoration(
                            color: isAdmin
                                ? theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.45)
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isAdmin
                                    ? (t('support_team') ?? 'Support Team')
                                    : (m['sender_name']?.toString() ??
                                        t('you') ??
                                        'You'),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isAdmin
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(m['body']?.toString() ?? ''),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (!_isClosed)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: t('type_message') ?? 'Type a message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
