import '../lang/translations.dart';

String mapBackendError(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('not verified') ||
      lower.contains('email not verified') ||
      lower.contains('email_not_verified') ||
      lower.contains('verify your email') ||
      lower.contains('before logging in')) {
    return t('email_not_verified');
  }
  if (lower.contains('turnstile_required') || lower.contains('human verification is required')) {
    return t('turnstile_required');
  }
  if (lower.contains('turnstile_failed') || lower.contains('human verification failed')) {
    return t('turnstile_failed');
  }
  if (lower.contains('duplicate_image') || lower.contains('image already exists in your store')) {
    return t('duplicate_image');
  }
  if (lower.contains('online_rate_limit') || lower.contains('only submit')) {
    return t('online_rate_limit');
  }
  if (lower.contains('pending_approval') || lower.contains('requires admin approval')) {
    return t('pending_approval');
  }
  if (lower.contains('invalid credentials') ||
      lower.contains('wrong password') ||
      lower.contains('email or password is incorrect')) {
    return t('invalid_credentials');
  }
  if (lower.contains('already registered') ||
      lower.contains('already exists')) {
    return t('already_registered');
  }
  if (lower.contains('not found')) {
    return t('not_found');
  }
  if (lower.contains('too many requests') || lower.contains('rate limit')) {
    return t('too_many_requests');
  }
  if (lower.contains('weak password') ||
      lower.contains('not strong enough') ||
      lower.contains('too weak') ||
      lower.contains('medium strength')) {
    return t('password_not_strong');
  }
  if (lower.contains('same as previous') ||
      lower.contains('cannot reuse') ||
      lower.contains('same as your previous')) {
    return t('password_reuse');
  }
  if (lower.contains('too many failed attempts') || lower.contains('locked')) {
    if (lower.contains('reset')) {
      return t('reset_code_locked');
    }
    return t('verification_code_locked');
  }
  if (lower.contains('expired') || lower.contains('no longer valid')) {
    return t('code_expired');
  }
  if ((lower.contains('incorrect') ||
          lower.contains('invalid') ||
          lower.contains('wrong')) &&
      (lower.contains('code') ||
          lower.contains('verification') ||
          lower.contains('reset') ||
          lower.contains('otp'))) {
    return t('code_incorrect');
  }
  if (lower.contains('please wait') || lower.contains('wait before')) {
    return t('please_wait_moment');
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return t('request_timeout');
  }
  if (lower.contains('network') || lower.contains('connection')) {
    return t('network_error');
  }
  if (lower.contains('unauthorized') || lower.contains('401')) {
    return t('session_expired');
  }
  if (lower.contains('forbidden') || lower.contains('403')) {
    return t('access_denied');
  }
  if (lower.contains('server error') ||
      lower.contains('500') ||
      lower.contains('something went wrong')) {
    return t('server_error');
  }
  return t('unknown_error');
}
