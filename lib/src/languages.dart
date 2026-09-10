/// Native display names for all languages the app ships translations for.
///
/// The list of supported locales itself is generated from the ARB files in
/// `lib/l10n/` (see `AppLocalizations.supportedLocales`), so adding a new
/// translation (e.g. via `tool/translate.py`) automatically makes it available
/// in the app. This map only provides the pretty name shown in the settings
/// dropdown; unknown codes fall back to the bare language code.
const Map<String, String> languageNativeNames = {
  'en': 'English',
  'de': 'Deutsch',
  'fr': 'Français',
  'ru': 'Русский',
  'es': 'Español',
  'pt': 'Português',
  'it': 'Italiano',
  'nl': 'Nederlands',
  'pl': 'Polski',
  'tr': 'Türkçe',
  'ar': 'العربية',
  'fa': 'فارسی',
  'he': 'עברית',
  'hi': 'हिन्दी',
  'bn': 'বাংলা',
  'ur': 'اردو',
  'id': 'Bahasa Indonesia',
  'ms': 'Bahasa Melayu',
  'vi': 'Tiếng Việt',
  'th': 'ไทย',
  'ja': '日本語',
  'ko': '한국어',
  'zh': '中文',
  'uk': 'Українська',
  'cs': 'Čeština',
  'sk': 'Slovenčina',
  'sv': 'Svenska',
  'nb': 'Norsk bokmål',
  'da': 'Dansk',
  'fi': 'Suomi',
  'el': 'Ελληνικά',
  'hu': 'Magyar',
  'ro': 'Română',
  'bg': 'Български',
  'hr': 'Hrvatski',
  'sr': 'Српски',
  'tl': 'Filipino',
  'ta': 'தமிழ்',
  'te': 'తెలుగు',
  'mr': 'मराठी',
};

/// Display name for a language code, falling back to the code itself.
String languageDisplayName(String languageCode) =>
    languageNativeNames[languageCode] ?? languageCode;
