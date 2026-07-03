import 'package:core_models/core_models.dart';
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

  /// Live ML-side stock per variation of a listing (empty for simple
  /// listings). Mirrored by `upsertItem`; managed in ML, shown for visibility.
  Stream<List<ListingVariation>> watchListingVariations(String listingId) {
    return _client
        .from('listing_variations')
        .stream(primaryKey: ['id'])
        .eq('ml_listing_id', listingId)
        .map((rows) => [for (final r in rows) ListingVariation.fromJson(r)]);
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

  /// Filas de la cola de push a ML que NO llegaron (status=error tras agotar
  /// reintentos, p. ej. sin conexión) o siguen pendientes hace rato. Antes
  /// esto fallaba en silencio; ahora alimenta el aviso del Inicio.
  Future<List<StockPushIssue>> pushIssues() async {
    final rows = await _client
        .from('stock_push_queue')
        .select('product_id, status, attempts, error, enqueued_at')
        .inFilter('status', ['error', 'pending'])
        .order('enqueued_at', ascending: true);
    final now = DateTime.now();
    return [
      for (final r in rows)
        if (r['status'] == 'error' ||
            // pending "viejo" (> 5 min) = el cron no está pudiendo drenarla.
            now
                    .difference(DateTime.tryParse('${r['enqueued_at']}') ?? now)
                    .inMinutes >=
                5)
          StockPushIssue(
            productId: r['product_id'] as String,
            status: r['status'] as String,
            attempts: (r['attempts'] as num?)?.toInt() ?? 0,
            error: r['error'] as String?,
          ),
    ];
  }

  /// Re-encola las filas en error y dispara el drenado de la cola.
  Future<void> retryPush() async {
    await _client.rpc('retry_stock_push');
    await _client.functions.invoke('push-stock');
  }
}

/// Un producto cuyo stock no pudo subirse a ML (o está demorado).
class StockPushIssue {
  const StockPushIssue({
    required this.productId,
    required this.status,
    required this.attempts,
    this.error,
  });

  final String productId;
  final String status;
  final int attempts;
  final String? error;
}
