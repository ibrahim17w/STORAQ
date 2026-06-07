import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../lang/translations.dart';
import '../providers/auth_provider.dart';
import '../services/review_service.dart';
import '../services/support_service.dart';
import 'guest_login_sheet.dart';

class ReviewsSection extends ConsumerStatefulWidget {
  final ReviewTargetType type;
  final int targetId;
  final String? targetName;
  final double? initialRating;
  final int? initialReviewCount;

  const ReviewsSection({
    super.key,
    required this.type,
    required this.targetId,
    this.targetName,
    this.initialRating,
    this.initialReviewCount,
  });

  @override
  ConsumerState<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends ConsumerState<ReviewsSection> {
  ReviewsPayload? _data;
  bool _loading = true;
  String? _error;
  int _selectedRating = 5;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  bool _showForm = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ReviewService.fetchReviews(
        type: widget.type,
        targetId: widget.targetId,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        if (data.myReview != null) {
          _selectedRating = data.myReview!.rating;
          _commentCtrl.text = data.myReview!.comment ?? '';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated || auth.isGuest) {
      showGuestSheet(context);
      return;
    }
    if (_data?.myReview != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('review_already_submitted') ?? 'You already submitted a review',
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ReviewService.submitReview(
        type: widget.type,
        targetId: widget.targetId,
        rating: _selectedRating,
        comment: _commentCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('review_submitted') ?? 'Review submitted'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() => _showForm = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _requestRemoval(Review review) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('request_review_removal') ?? 'Request Review Removal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('request_review_removal_hint') ??
                  'Only STORAQ admins can remove reviews. Explain why this review should be removed.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: t('removal_reason_hint') ?? 'Valid reason (min 20 chars)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel') ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('submit') ?? 'Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reasonCtrl.dispose();
      return;
    }

    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (reason.length < 20) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('removal_reason_too_short') ?? 'Please provide at least 20 characters',
          ),
        ),
      );
      return;
    }

    final typeLabel = widget.type == ReviewTargetType.store ? 'store' : 'product';
    final name = widget.targetName ?? '#${widget.targetId}';
    try {
      await SupportService.createTicket(
        subject: 'Review removal — $typeLabel review #${review.id}',
        category: 'review_removal',
        body: 'Review removal request\n'
            'Type: $typeLabel\n'
            'Target: $name (ID ${widget.targetId})\n'
            'Review ID: ${review.id}\n'
            'Rating: ${review.rating}/5\n'
            'Reviewer: ${review.userName ?? 'Unknown'}\n'
            'Comment: ${review.comment ?? '(none)'}\n\n'
            'Reason for removal:\n$reason',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('review_removal_ticket_sent') ??
                'Support ticket sent — an admin will review your request',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Widget _stars(double rating, {double size = 18}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.round();
        return Icon(
          filled ? Icons.star : Icons.star_border,
          size: size,
          color: Colors.amber.shade700,
        );
      }),
    );
  }

  Widget _ratingPicker() {
    return Row(
      children: List.generate(5, (i) {
        final value = i + 1;
        final selected = value <= _selectedRating;
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: _submitting
              ? null
              : () => setState(() => _selectedRating = value),
          icon: Icon(
            selected ? Icons.star : Icons.star_border,
            color: Colors.amber.shade700,
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = _data?.rating ?? widget.initialRating ?? 5.0;
    final total = _data?.total ?? widget.initialReviewCount ?? 0;
    final canRequestRemoval = _data?.canRequestRemoval == true;
    final canWriteReview = !canRequestRemoval;

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  t('reviews') ?? 'Reviews',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _stars(rating),
                const SizedBox(width: 6),
                Text(
                  '${rating.toStringAsFixed(1)} ($total)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (canRequestRemoval)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t('owner_review_removal_info') ??
                      'Only admins can remove reviews. Tap "Request removal" on any review to open a support ticket.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
              )
            else ...[
              if (_data!.reviews.isEmpty)
                Text(
                  t('no_reviews_yet') ?? 'No reviews yet',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                )
              else
                ..._data!.reviews.take(5).map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _stars(r.rating.toDouble(), size: 14),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r.userName ?? t('customer') ?? 'Customer',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (canRequestRemoval)
                                TextButton(
                                  onPressed: () => _requestRemoval(r),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                  ),
                                  child: Text(
                                    t('request_removal') ?? 'Request removal',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (r.comment != null && r.comment!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                r.comment!,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    )),
              const SizedBox(height: 8),
              if (canWriteReview &&
                  _data!.myReview == null &&
                  !_showForm)
                OutlinedButton.icon(
                  onPressed: () {
                    final auth = ref.read(authProvider);
                    if (!auth.isAuthenticated || auth.isGuest) {
                      showGuestSheet(context);
                      return;
                    }
                    setState(() => _showForm = true);
                  },
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: Text(t('write_review') ?? 'Write a Review'),
                ),
              if (canWriteReview &&
                  _showForm &&
                  _data!.myReview == null) ...[
                Text(
                  t('your_rating') ?? 'Your rating',
                  style: theme.textTheme.labelLarge,
                ),
                _ratingPicker(),
                TextField(
                  controller: _commentCtrl,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    hintText: t('review_comment_hint') ??
                        'Share your experience (optional)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _showForm = false),
                      child: Text(t('cancel') ?? 'Cancel'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(t('submit_review') ?? 'Submit Review'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
