// lib/widgets/turnstile_widget.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

/// Cloudflare Turnstile site key — replace with your actual key.
/// In dev/test, use Cloudflare's always-pass test key.
const String _turnstileSiteKey = const String.fromEnvironment(
  'TURNSTILE_SITE_KEY',
  defaultValue: '1x00000000000000000000AA', // Cloudflare always-pass test key
);

/// A minimal Turnstile widget that auto-solves in the background.
/// On mobile (non-web), it calls a lightweight server endpoint to get
/// a pre-verified token, or renders an invisible challenge via a simple HTTP call.
///
/// For production, you'd embed a WebView with the Turnstile JS widget.
/// This implementation provides the token via an invisible server-side check.
class TurnstileWidget extends StatefulWidget {
  final ValueChanged<String?> onToken;

  const TurnstileWidget({super.key, required this.onToken});

  @override
  State<TurnstileWidget> createState() => _TurnstileWidgetState();
}

class _TurnstileWidgetState extends State<TurnstileWidget> {
  bool _loading = true;
  bool _verified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _requestToken();
  }

  Future<void> _requestToken() async {
    // In dev mode (no TURNSTILE_SITE_KEY env), just pass a dummy token
    if (_turnstileSiteKey == '1x00000000000000000000AA') {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          _loading = false;
          _verified = true;
        });
        widget.onToken('dev-mode-pass');
      }
      return;
    }

    try {
      // Request a turnstile challenge token from our backend proxy
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/auth/turnstile-challenge'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String?;
        if (mounted) {
          setState(() {
            _loading = false;
            _verified = token != null && token.isNotEmpty;
          });
          widget.onToken(token);
        }
      } else {
        // Fallback: pass empty token; server will validate
        if (mounted) {
          setState(() {
            _loading = false;
            _verified = false;
            _error = 'Verification unavailable';
          });
          widget.onToken(null);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _verified = false;
          _error = 'Verification failed';
        });
        widget.onToken(null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Verifying...',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    if (_verified) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user, size: 16, color: Colors.green.shade600),
            const SizedBox(width: 6),
            Text(
              'Verified',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Error state with retry
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber, size: 16, color: Colors.orange.shade600),
          const SizedBox(width: 6),
          Text(
            _error ?? 'Verification failed',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade600),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _requestToken();
            },
            child: Text(
              'Retry',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
