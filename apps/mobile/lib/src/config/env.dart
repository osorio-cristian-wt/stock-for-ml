import 'dart:io' show Platform;

/// App configuration, provided at build time via --dart-define.
///
/// Local defaults point at the Supabase stack on the 743x ports. For cloud,
/// pass values explicitly, e.g.:
/// `flutter run --dart-define=SUPABASE_URL=https://PROJECT.supabase.co
/// --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx`
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:7431',
  );

  /// [supabaseUrl] adjusted for the runtime host. On the Android emulator the
  /// host machine is reachable at 10.0.2.2 (127.0.0.1 there is the emulator
  /// itself), so local URLs are rewritten automatically. iOS simulator and
  /// desktop reach the host on 127.0.0.1 as-is, and cloud URLs pass through.
  ///
  /// Note: a *physical* Android device needs your PC's LAN IP instead —
  /// pass it via `--dart-define=SUPABASE_URL=http://192.168.x.x:7431`.
  static String get resolvedSupabaseUrl {
    final url = supabaseUrl;
    if (Platform.isAndroid &&
        (url.contains('127.0.0.1') || url.contains('localhost'))) {
      return url
          .replaceFirst('127.0.0.1', '10.0.2.2')
          .replaceFirst('localhost', '10.0.2.2');
    }
    return url;
  }

  /// Local "publishable" (anon) key printed by `supabase start`.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );

  /// Deep-link scheme used for the ML OAuth callback redirect.
  static const String authCallbackScheme = 'stockforml';

  static bool get isLocal => supabaseUrl.contains('127.0.0.1');
}
