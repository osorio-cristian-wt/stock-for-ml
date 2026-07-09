import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'queries.dart';
import 'supabase_providers.dart';

/// RF-36: dispara el import de publicaciones y va drenando lotes mientras la
/// app está abierta (cada llamada al server procesa ~15 ítems y devuelve el
/// estado). El progreso NO vive acá: la UI lo lee de importJobsStreamProvider
/// (Realtime sobre `import_jobs`), así el banner también avanza si la app se
/// cierra y los lotes los termina el cron del backend.
class ImportService {
  ImportService(this._ref);

  final Ref _ref;
  bool _running = false;

  /// Arranca (o retoma) el import y drena lotes hasta terminar. Reentrante:
  /// si ya hay un drenado en curso, no lanza otro.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final jobs =
            await _ref.read(connectionRepositoryProvider).importBatch();
        if (!jobs.any((j) => j.isRunning)) break;
      }
    } finally {
      _running = false;
      // Catálogo actualizado: refrescar lo derivado.
      _ref.invalidate(productsStreamProvider);
      _ref.invalidate(economicsProvider);
      _ref.invalidate(fullInboundsProvider);
    }
  }
}

final importServiceProvider = Provider<ImportService>((ref) {
  return ImportService(ref);
});
