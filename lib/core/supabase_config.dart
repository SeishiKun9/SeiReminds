/// Public Supabase client configuration (publishable key only — never secret/service_role).
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rindujmseujfoiuoqped.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_MiaTWnWsPEdSVvsdH1-nTw_udDvkFYV',
  );

  static const String authRedirectUrl =
      'com.seireminds.seireminds://login-callback/';
}
