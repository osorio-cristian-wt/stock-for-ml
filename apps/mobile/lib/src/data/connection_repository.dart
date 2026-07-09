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

  /// Arranca (o retoma) el import de publicaciones y procesa UN lote (RF-36).
  /// El server crea un job persistente por cuenta; llamar de nuevo continúa
  /// desde donde quedó (idempotente). Devuelve el estado de los jobs.
  Future<List<ImportJob>> importBatch() async {
    final res = await _client.functions.invoke('sync-items');
    final data = res.data as Map<String, dynamic>?;
    final jobs = (data?['jobs'] as List?) ?? const [];
    return [
      for (final j in jobs) ImportJob.fromJson((j as Map).cast<String, dynamic>()),
    ];
  }

  /// Progreso en vivo de los imports (Realtime sobre `import_jobs`): el
  /// banner sigue avanzando aunque el lote lo procese el cron y no la app.
  Stream<List<ImportJob>> watchImportJobs() {
    return _client
        .from('import_jobs')
        .stream(primaryKey: ['id'])
        .order('started_at')
        .map((rows) => [for (final r in rows) ImportJob.fromJson(r)]);
  }

  /// Ingresos a Full detectados y pendientes de atribuir (RF-38).
  Future<List<FullInbound>> pendingFullInbounds() async {
    final rows = await _client
        .from('full_inbounds')
        .select()
        .eq('status', 'pending')
        .order('detected_at', ascending: false);
    return [for (final r in rows) FullInbound.fromJson(r)];
  }

  /// La mercadería salió de [warehouseId]: descuenta SOLO local (sin push).
  Future<void> attributeFullInbound({
    required String inboundId,
    required String warehouseId,
  }) async {
    await _client.rpc('attribute_full_inbound', params: {
      'p_inbound_id': inboundId,
      'p_warehouse_id': warehouseId,
    });
  }

  /// No salió de un depósito local (p. ej. compra directa a Full).
  Future<void> dismissFullInbound(String inboundId) async {
    await _client.rpc('dismiss_full_inbound', params: {
      'p_inbound_id': inboundId,
    });
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

  /// Todas las publicaciones ML vinculadas a un producto, en vivo (RF-48):
  /// un producto puede tener varias (relistings, tipos de publicación).
  Stream<List<MlListing>> watchProductListings(String productId) {
    return _client
        .from('ml_listings')
        .stream(primaryKey: ['id'])
        .eq('product_id', productId)
        .map((rows) => [for (final r in rows) MlListing.fromJson(r)]);
  }

  /// Cantidad total de publicaciones espejadas (para el contador de la
  /// pestaña Productos: "N productos · M publicaciones").
  Stream<int> watchListingCount() {
    return _client
        .from('ml_listings')
        .stream(primaryKey: ['id'])
        .map((rows) => rows.length);
  }

  /// Busca publicaciones ESPEJADAS (RF-41): sync-items ya trae todas las del
  /// vendedor a `ml_listings`, así que el picker de vinculación no necesita
  /// consultar ML — busca sobre la base propia por título o código.
  Future<List<MlListing>> searchListings(String query, {int limit = 25}) async {
    var builder = _client.from('ml_listings').select();
    final q = query.trim().replaceAll(RegExp(r'[,()"\\]'), ' ').trim();
    if (q.isNotEmpty) {
      builder = builder.or('title.ilike.%$q%,ml_item_id.ilike.%$q%');
    }
    final rows = await builder.order('title').limit(limit);
    return [for (final r in rows) MlListing.fromJson(r)];
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

  /// RF-46 · Actividad ML: últimos pushes de stock (cola completa, no solo
  /// los fallidos como [pushIssues]).
  Future<List<StockPushEntry>> recentPushes({int limit = 50}) async {
    final rows = await _client
        .from('stock_push_queue')
        .select('product_id, status, attempts, error, enqueued_at, processed_at')
        .order('enqueued_at', ascending: false)
        .limit(limit);
    return [for (final r in rows) StockPushEntry.fromJson(r)];
  }

  /// RF-46 · Actividad ML: movimientos que LLEGARON desde ML (ventas
  /// reconciliadas, espejo Full, siembras de import).
  Future<List<StockMovement>> recentMlMovements({int limit = 50}) async {
    final rows = await _client
        .from('stock_movements')
        .select()
        .eq('origin', 'ml')
        .order('created_at', ascending: false)
        .limit(limit);
    return [for (final r in rows) StockMovement.fromJson(r)];
  }

  /// RF-46 · Actividad ML: historial de imports (terminados incluidos).
  Future<List<ImportJob>> recentImportJobs({int limit = 10}) async {
    final rows = await _client
        .from('import_jobs')
        .select()
        .order('started_at', ascending: false)
        .limit(limit);
    return [for (final r in rows) ImportJob.fromJson(r)];
  }

  /// RF-47/RF-48: cambia el estado de publicaciones en ML vía Edge Function
  /// (`active` reactiva, `paused` pausa). Las pausadas por falta de stock no
  /// necesitan reactivación explícita: el push de stock las reactiva solo.
  Future<void> setListingStatus(List<String> mlItemIds, String status) async {
    final res = await _client.functions.invoke('reactivate-listing', body: {
      'ml_item_ids': mlItemIds,
      'status': status,
    });
    final data = res.data as Map<String, dynamic>?;
    final errors = (data?['errors'] as List?) ?? const [];
    if (errors.isNotEmpty) {
      throw StateError(errors.join(' · '));
    }
  }

  Future<void> reactivateListings(List<String> mlItemIds) =>
      setListingStatus(mlItemIds, 'active');

  /// RF-49: recalibra el stock vendible de TODOS los productos — publicados
  /// quedan en el available de su publicación ML, internos en 0. No pushea
  /// nada a ML. Devuelve cuántos productos se ajustaron.
  Future<int> recalibrateStock() async {
    final res = await _client.rpc('recalibrate_stock');
    return (res as num?)?.toInt() ?? 0;
  }

  /// RF-45: revoca credenciales y desvincula la cuenta ML. El histórico
  /// (productos, ventas, espejos) se CONSERVA — solo deja de sincronizar.
  Future<void> disconnectMl() async {
    await _client.rpc('disconnect_ml');
  }

  /// RF-45: borra TODOS los datos del perfil en la nube (transaccional,
  /// scoped al propio profile_id en el server).
  Future<void> wipeAllData() async {
    await _client.rpc('wipe_profile_data');
  }
}

/// RF-46: una fila de la cola de push (para la línea de tiempo de Actividad).
class StockPushEntry {
  const StockPushEntry({
    required this.productId,
    required this.status,
    required this.attempts,
    this.error,
    this.enqueuedAt,
    this.processedAt,
  });

  final String productId;
  final String status;
  final int attempts;
  final String? error;
  final DateTime? enqueuedAt;
  final DateTime? processedAt;

  factory StockPushEntry.fromJson(Map<String, dynamic> j) => StockPushEntry(
        productId: j['product_id'] as String,
        status: (j['status'] as String?) ?? 'pending',
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
        enqueuedAt: DateTime.tryParse('${j['enqueued_at']}'),
        processedAt: j['processed_at'] == null
            ? null
            : DateTime.tryParse('${j['processed_at']}'),
      );
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
