import 'package:supabase_flutter/supabase_flutter.dart';

import 'membership.dart';

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

  /// Starts a new shop owned by this user.
  ///
  /// Deliberately *not* automatic on sign-in. Someone joining their employer's
  /// shop must not have a phantom shop of their own created first — they would
  /// then be told they already belong somewhere and could never redeem their
  /// code.
  ///
  /// One server-side call rather than three round trips: creating the business
  /// and the membership separately cannot work under RLS, because reading back
  /// the new business requires a membership that does not exist until the step
  /// after. See migration 0004.
  Future<String?> createMyShop({required String shopName}) async {
    final c = client;
    if (c == null || c.auth.currentUser == null) return null;

    return c.rpc<String?>(
      'create_business_for_me',
      params: {'shop_name': shopName},
    );
  }

  /// This user's role in their shop, or null when signed out or unreachable.
  Future<Membership?> fetchMembership() async {
    final c = client;
    if (c == null || c.auth.currentUser == null) return null;

    final rows = await c.rpc<List<dynamic>>('my_membership');
    if (rows.isEmpty) return null;

    final row = rows.first as Map<String, dynamic>;
    return Membership(
      role: Membership.roleFrom(row['role'] as String?),
      businessId: row['business_id'] as String?,
      canSeeProfitFlag: row['can_see_profit'] == true,
    );
  }

  /// Owner generates a code for a new member of staff.
  Future<String> createInvite({
    required ShopRole role,
    bool canSeeProfit = false,
  }) async {
    final c = client;
    if (c == null) throw StateError('Cloud backup is not set up.');

    final code = await c.rpc<String>('create_staff_invite', params: {
      'staff_role': role == ShopRole.manager ? 'manager' : 'cashier',
      'sees_profit': canSeeProfit,
    });
    return code;
  }

  /// Staff join an existing shop with a code the owner read out.
  Future<String?> redeemInvite(String code) async {
    final c = client;
    if (c == null) throw StateError('Cloud backup is not set up.');
    return c.rpc<String?>('redeem_staff_invite', params: {'invite_code': code});
  }

  Future<List<StaffMember>> listStaff() async {
    final c = client;
    if (c == null || c.auth.currentUser == null) return const [];

    final rows = await c.rpc<List<dynamic>>('list_staff');
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        StaffMember(
          userId: row['user_id'] as String,
          name: row['full_name'] as String? ?? '',
          phone: row['phone'] as String? ?? '',
          role: Membership.roleFrom(row['role'] as String?),
          canSeeProfit: row['can_see_profit'] == true,
          isMe: row['is_me'] == true,
        ),
    ];
  }

  Future<void> removeStaff(String userId) async {
    final c = client;
    if (c == null) throw StateError('Cloud backup is not set up.');
    await c.rpc<void>('remove_staff', params: {'member_user_id': userId});
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
