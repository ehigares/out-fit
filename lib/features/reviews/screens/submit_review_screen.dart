import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/review_provider.dart';

class SubmitReviewScreen extends ConsumerStatefulWidget {
  const SubmitReviewScreen({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<SubmitReviewScreen> createState() => _SubmitReviewScreenState();
}

class _SubmitReviewScreenState extends ConsumerState<SubmitReviewScreen> {
  int _rating = 0;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating.')),
      );
      return;
    }

    final ok = await ref.read(reviewNotifierProvider.notifier).submitReview(
          eventId: widget.eventId,
          rating: _rating,
          comment: _commentCtrl.text,
        );

    if (!mounted) return;

    if (ok) {
      ref.invalidate(eventReviewsProvider(widget.eventId));
      ref.invalidate(myReviewProvider(widget.eventId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review submitted!'),
          backgroundColor: Colors.green,
        ),
      );
      context.pop();
    } else {
      final err = ref.read(reviewNotifierProvider);
      err.whenOrNull(
        error: (e, _) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myReviewAsync = ref.watch(myReviewProvider(widget.eventId));
    final saving = ref.watch(reviewNotifierProvider) is AsyncLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Write a Review')),
      body: myReviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not load review data')),
        data: (existing) {
          // Pre-fill if editing existing review
          if (existing != null && _rating == 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() => _rating = existing.rating);
              if (existing.comment != null) {
                _commentCtrl.text = existing.comment!;
              }
            });
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (existing != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'You already reviewed this event. Submit again to update your review.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),

                Text(
                  'Rate this event',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                    'Your review helps the community make better choices.'),
                const SizedBox(height: 24),

                // Star rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (i) => GestureDetector(
                      onTap: () => setState(() => _rating = i + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          i < _rating ? Icons.star : Icons.star_border,
                          size: 44,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _ratingLabel(_rating),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _rating > 0
                        ? Colors.amber.shade700
                        : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),

                // Comment
                TextField(
                  controller: _commentCtrl,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Comment (optional)',
                    alignLabelWithHint: true,
                    hintText: 'Share your experience...',
                  ),
                ),
                const SizedBox(height: 32),

                ElevatedButton(
                  onPressed: saving ? null : _submit,
                  child: saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          existing != null ? 'Update Review' : 'Submit Review'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _ratingLabel(int r) {
    switch (r) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      case 5:
        return 'Excellent!';
      default:
        return 'Tap a star to rate';
    }
  }
}
