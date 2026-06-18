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

  /// Local "publishable" (anon) key printed by `supabase start`.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );

  /// Deep-link scheme used for the ML OAuth callback redirect.
  static const String authCallbackScheme = 'stockforml';

  static bool get isLocal => supabaseUrl.contains('127.0.0.1');
}
