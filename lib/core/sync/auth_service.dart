import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign-in and shop membership.
///
/// The app never blocks on this: a shop can trade all day signed out, and only
/// needs an account to get its records off the phone (design doc 4.11).
class AuthService {
  SupabaseClient? get client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null; // running without --dart-define, purely offline
    }
  }

  bool get isConfigured => client != null;
  User? get currentUser => client?.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  Stream<AuthState>? get changes => client?.auth.onAuthStateChange;

  /// Sends the six-digit code. Phone is normalised to the international form
  /// Supabase expects.
  Future<void> sendOtp(String phone) async {
    final c = client;
    if (c == null) throw StateError('Cloud backup is not set up.');
    await c.auth.signInWithOtp(phone: normalisePhone(phone));
  }

  Future<void> verifyOtp({required String phone, required String code}) async {
    final c = client;
    if (c == null) throw StateError('Cloud backup is not set up.');
    await c.auth.verifyOTP(
      type: OtpType.sms,
      phone: normalisePhone(phone),
      token: code.trim(),
    );
  }

  /// The scheme AndroidManifest.xml registers an intent-filter for, so the
  /// browser can hand control back to the app once Google sign-in finishes.
  /// Without this, the OAuth flow completes in the browser and just strands
  /// the user there.
  static const _oauthRedirect = 'ng.shoppadi.shoppadi://login-callback';

  Future<void> signInWithGoogle() async {
    final c = client;
    if (c == null) throw StateError('Cloud backup is not set up.');
    await c.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirect,
    );
  }

  Future<void> signOut() async => client?.auth.signOut();

  /// The shop this user belongs to, creating it on first sign-in. Returns null
  /// when offline — the caller keeps working locally and tries again later.
  ///
  /// Done in one server-side call rather than three round trips. Creating the
  /// business and the membership row separately cannot work under RLS: reading
  /// back the new business requires membership, which does not exist until the
  /// step after. See migration 0004.
  Future<String?> ensureBusiness({required String shopName}) async {
    final c = client;
    if (c == null || c.auth.currentUser == null) return null;

    final id = await c.rpc<String?>(
      'create_business_for_me',
      params: {'shop_name': shopName},
    );
    return id;
  }

  /// 0803…, 803…, +234803… and 00234803… all become +234803…
  static String normalisePhone(String raw, {String countryCode = '234'}) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0')) {
      digits = '$countryCode${digits.substring(1)}';
    } else if (!digits.startsWith(countryCode) && digits.length <= 10) {
      digits = '$countryCode$digits';
    }
    return '+$digits';
  }
}
