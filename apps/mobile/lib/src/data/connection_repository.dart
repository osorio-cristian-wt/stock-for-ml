import 'package:supabase_flutter/supabase_flutter.dart';

/// A linked MercadoLibre account (row of `public.ml_accounts`).
class MlAccount {
  const MlAccount({
    required this.id,
    required this.mlUserId,
    this.nickname,
    this.siteId = 'MLA',
    this.connectedAt,
  });

  final String id;
  final int mlUserId;
  final String? nickname;
  final String siteId;
  final DateTime? connectedAt;

  factory MlAccount.fromJson(Map<String, dynamic> j) => MlAccount(
        id: j['id'] as String,
        mlUserId: (j['ml_user_id'] as num).toInt(),
        nickname: j['nickname'] as String?,
        siteId: (j['site_id'] as String?) ?? 'MLA',
        connectedAt: j['connected_at'] == null
            ? null
            : DateTime.tryParse(j['connected_at'] as String),
      );
}

/// Drives the OAuth handshake with MercadoLibre. The app never talks to ML
/// directly: it asks the `oauth-url` Edge Function for an authorize URL (PKCE
/// state persisted server-side) and later reads `ml_accounts` to know if the
/// `oauth-callback` function finished linking the account.
class ConnectionRepository {
  ConnectionRepository(this._client);

  final SupabaseClient _client;

  /// The currently linked ML account, or null if none.
  Future<MlAccount?> currentAccount() async {
    final row = await _client
        .from('ml_accounts')
        .select()
        .order('connected_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : MlAccount.fromJson(row);
  }

  /// Requests the ML authorization URL to open in the system browser.
  Future<Uri> authorizeUrl() async {
    final res = await _client.functions.invoke('oauth-url');
    final data = res.data as Map<String, dynamic>?;
    final url = data?['authorize_url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('El backend no devolvió la URL de autorización.');
    }
    return Uri.parse(url);
  }

  /// Kicks off the first import (publications) after linking. Best-effort.
  Future<void> triggerInitialSync() async {
    await _client.functions.invoke('sync-items');
  }

  /// Links an existing ML publication (e.g. "MLA123") to an internal product.
  /// Read-only ML access; the publication's title stays independent from stock.
  Future<void> linkListing({
    required String productId,
    required String mlItemId,
  }) async {
    final res = await _client.functions.invoke('link-ml-listing', body: {
      'product_id': productId,
      'ml_item_id': mlItemId,
    });
    final data = res.data as Map<String, dynamic>?;
    if (data == null || data['error'] != null) {
      throw StateError(data?['error']?.toString() ?? 'No se pudo vincular.');
    }
  }
}
