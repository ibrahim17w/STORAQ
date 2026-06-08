import 'package:flutter/material.dart';
import '../lang/translations.dart';
import '../services/chat_service.dart';
import '../widgets/cached_image.dart';
import 'chat_screen.dart';

class ChatConversationsScreen extends StatefulWidget {
  const ChatConversationsScreen({super.key});

  @override
  State<ChatConversationsScreen> createState() =>
      _ChatConversationsScreenState();
}

class _ChatConversationsScreenState extends State<ChatConversationsScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ChatService.fetchConversations();
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _confirmDeleteConversation(Map<String, dynamic> conversation) async {
    final id = (conversation['id'] as num?)?.toInt();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('delete') ?? 'Delete'),
        content: Text(
          t('delete_chat_confirm') ??
              'Delete this conversation and all messages?',
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
      await ChatService.deleteConversation(id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void _openChat(Map<String, dynamic> conversation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(conversation: conversation),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('messages') ?? 'Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: Text(t('retry') ?? 'Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _conversations.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 56,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t('no_messages_yet') ?? 'No messages yet',
                            style: TextStyle(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t('chat_from_store') ??
                                'Message a store from a product page',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _conversations.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = _conversations[i];
                          final title = c['customer_label']?.toString() ??
                              c['store_name']?.toString() ??
                              t('store');
                          final subtitle =
                              c['last_message']?.toString() ?? '';
                          final unread = (c['unread_count'] as num?)?.toInt() ?? 0;
                          final isStoreChat = c['store_name'] != null &&
                              c['customer_label'] == null;
                          final imageUrl = isStoreChat
                              ? c['store_image_url']?.toString()
                              : c['customer_avatar_url']?.toString();

                          return ListTile(
                            onLongPress: () => _confirmDeleteConversation(c),
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              child: imageUrl != null && imageUrl.isNotEmpty
                                  ? ClipOval(
                                      child: CachedAppImage(
                                        imageUrl: imageUrl,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 80,
                                      ),
                                    )
                                  : Icon(
                                      isStoreChat
                                          ? Icons.storefront
                                          : Icons.person_outline,
                                      color: theme.colorScheme.primary,
                                    ),
                            ),
                            title: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              subtitle,
                              maxLines: 1,
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
                                  const Icon(Icons.chevron_right, size: 18),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  tooltip: t('delete') ?? 'Delete',
                                  onPressed: () => _confirmDeleteConversation(c),
                                ),
                              ],
                            ),
                            onTap: () => _openChat(c),
                          );
                        },
                      ),
                    ),
    );
  }
}
