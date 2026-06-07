import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import '../lang/translations.dart';

import '../services/api_service.dart';

import '../services/support_service.dart';

import '../widgets/cached_image.dart';



class SupportTicketScreen extends StatefulWidget {

  final Map<String, dynamic> ticket;



  const SupportTicketScreen({super.key, required this.ticket});



  @override

  State<SupportTicketScreen> createState() => _SupportTicketScreenState();

}



class _SupportTicketScreenState extends State<SupportTicketScreen> {

  final _controller = TextEditingController();

  final _scrollController = ScrollController();

  final _picker = ImagePicker();

  Map<String, dynamic>? _ticket;

  List<Map<String, dynamic>> _messages = [];

  bool _loading = true;

  bool _sending = false;

  bool _imageBusy = false;

  Timer? _pollTimer;



  int get _ticketId => (widget.ticket['id'] as num?)?.toInt() ?? 0;



  bool get _isClosed => _ticket?['status']?.toString() == 'closed';



  int get _imageQuota => (_ticket?['image_quota'] as num?)?.toInt() ?? 0;



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



  String _resolveAttachmentUrl(String? url) {

    if (url == null || url.isEmpty) return '';

    if (url.startsWith('http://') || url.startsWith('https://')) return url;

    return '${ApiService.baseUrl}$url';

  }

  Future<void> _confirmDeleteTicket() async {
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
      await SupportService.deleteTicket(_ticketId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
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



  Future<void> _requestImagePermission() async {

    if (_imageBusy || _isClosed) return;

    setState(() => _imageBusy = true);

    try {

      final sent = await SupportService.requestImageUpload(_ticketId);

      if (!mounted) return;

      setState(() {

        _messages = [..._messages, sent];

        _imageBusy = false;

      });

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(

          content: Text(

            t('image_request_sent') ??

                'Image request sent. Support will approve in this chat.',

          ),

        ),

      );

    } catch (e) {

      if (!mounted) return;

      setState(() => _imageBusy = false);

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(content: Text(e.toString())),

      );

    }

  }



  Future<void> _pickAndUploadImage() async {

    if (_imageBusy || _isClosed) return;

    if (_imageQuota < 1) {

      await _requestImagePermission();

      return;

    }



    final picked = await _picker.pickImage(

      source: ImageSource.gallery,

      maxWidth: 1920,

      maxHeight: 1920,

      imageQuality: 85,

    );

    if (picked == null) return;



    setState(() => _imageBusy = true);

    try {

      final sent = await SupportService.uploadImage(

        _ticketId,

        File(picked.path),

      );

      if (!mounted) return;

      await _load(silent: true);

      if (!mounted) return;

      setState(() {

        if (!_messages.any((m) => m['id'] == sent['id'])) {

          _messages = [..._messages, sent];

        }

        _imageBusy = false;

      });

    } catch (e) {

      if (!mounted) return;

      setState(() => _imageBusy = false);

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(content: Text(e.toString())),

      );

    }

  }



  Widget _buildMessageBubble(Map<String, dynamic> m, ThemeData theme) {

    final isAdmin = m['sender_role']?.toString() == 'admin';

    final type = m['message_type']?.toString() ?? 'text';

    final isSystem = type == 'system';

    final isImageRequest = type == 'image_request';

    final isImage = type == 'image';

    final attachment = _resolveAttachmentUrl(m['attachment_url']?.toString());



    Color bubbleColor;

    if (isSystem) {

      bubbleColor = theme.colorScheme.secondaryContainer.withValues(alpha: 0.45);

    } else if (isImageRequest) {

      bubbleColor = theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5);

    } else if (isAdmin) {

      bubbleColor = theme.colorScheme.primaryContainer.withValues(alpha: 0.45);

    } else {

      bubbleColor = theme.colorScheme.surfaceContainerHighest;

    }



    return Align(

      alignment: isAdmin || isSystem ? Alignment.centerLeft : Alignment.centerRight,

      child: Container(

        margin: const EdgeInsets.only(bottom: 10),

        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

        constraints: BoxConstraints(

          maxWidth: MediaQuery.sizeOf(context).width * 0.78,

        ),

        decoration: BoxDecoration(

          color: bubbleColor,

          borderRadius: BorderRadius.circular(14),

          border: isImageRequest

              ? Border.all(

                  color: theme.colorScheme.tertiary.withValues(alpha: 0.4),

                )

              : null,

        ),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Text(

              isSystem

                  ? (t('support_team') ?? 'Support Team')

                  : isAdmin

                      ? (t('support_team') ?? 'Support Team')

                      : (m['sender_name']?.toString() ?? t('you') ?? 'You'),

              style: theme.textTheme.labelSmall?.copyWith(

                fontWeight: FontWeight.w700,

                color: isAdmin || isSystem

                    ? theme.colorScheme.primary

                    : theme.colorScheme.onSurfaceVariant,

              ),

            ),

            if (isImageRequest) ...[

              const SizedBox(height: 4),

              Row(

                children: [

                  Icon(

                    Icons.image_outlined,

                    size: 16,

                    color: theme.colorScheme.tertiary,

                  ),

                  const SizedBox(width: 6),

                  Expanded(

                    child: Text(

                      t('image_upload_requested') ??

                          'Image upload requested — awaiting approval',

                      style: theme.textTheme.bodySmall?.copyWith(

                        fontStyle: FontStyle.italic,

                      ),

                    ),

                  ),

                ],

              ),

            ],

            if (isImage && attachment.isNotEmpty) ...[

              const SizedBox(height: 8),

              ClipRRect(

                borderRadius: BorderRadius.circular(10),

                child: GestureDetector(

                  onTap: () => showDialog(

                    context: context,

                    builder: (_) => Dialog(

                      child: InteractiveViewer(

                        child: CachedAppImage(

                          imageUrl: attachment,

                          fit: BoxFit.contain,

                        ),

                      ),

                    ),

                  ),

                  child: CachedAppImage(

                    imageUrl: attachment,

                    width: 200,

                    height: 160,

                    fit: BoxFit.cover,

                    memCacheWidth: 400,

                  ),

                ),

              ),

            ],

            if ((m['body']?.toString() ?? '').isNotEmpty) ...[

              const SizedBox(height: 4),

              Text(m['body']?.toString() ?? ''),

            ],

          ],

        ),

      ),

    );

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

        actions: [

          if (_imageQuota > 0 && !_isClosed)

            Padding(

              padding: const EdgeInsets.only(right: 8),

              child: Chip(

                label: Text(

                  '${t('images_allowed') ?? 'Images'}: $_imageQuota',

                  style: theme.textTheme.labelSmall,

                ),

                visualDensity: VisualDensity.compact,

              ),

            ),

          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: t('delete') ?? 'Delete',
            onPressed: _confirmDeleteTicket,
          ),

        ],

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

                    itemBuilder: (_, i) => _buildMessageBubble(_messages[i], theme),

                  ),

          ),

          if (!_isClosed)

            SafeArea(

              child: Padding(

                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),

                child: Row(

                  children: [

                    IconButton(

                      tooltip: _imageQuota > 0

                          ? (t('attach_image') ?? 'Attach image')

                          : (t('request_image_upload') ?? 'Request image upload'),

                      onPressed: _imageBusy

                          ? null

                          : (_imageQuota > 0

                              ? _pickAndUploadImage

                              : _requestImagePermission),

                      icon: _imageBusy

                          ? const SizedBox(

                              width: 20,

                              height: 20,

                              child: CircularProgressIndicator(strokeWidth: 2),

                            )

                          : Icon(

                              _imageQuota > 0

                                  ? Icons.attach_file_rounded

                                  : Icons.image_outlined,

                            ),

                    ),

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

