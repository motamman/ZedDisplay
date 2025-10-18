# Configuration Setup

This project uses a configuration file to store sensitive data like API keys.

## Note About Syncfusion

**Syncfusion no longer requires license registration** - the license is handled automatically. The configuration setup below is for future use with other API keys or sensitive data.

## Initial Setup (Optional)

If you need to store other configuration values:

1. **Copy the example config file:**
   ```bash
   cp lib/config/app_config.example.dart lib/config/app_config.dart
   ```

2. **Edit `lib/config/app_config.dart` and add your values**

3. **The `app_config.dart` file is git-ignored** to prevent committing sensitive data

## File Structure

- `lib/config/app_config.dart` - Your actual config (git-ignored, contains real keys)
- `lib/config/app_config.example.dart` - Template for other developers (committed to git)

## Adding New Configuration Values

To add new configuration values:

1. Add the constant to both `app_config.dart` and `app_config.example.dart`
2. In `app_config.example.dart`, use placeholder values
3. In `app_config.dart`, use your actual values
4. Import and use: `import 'package:zed_display/config/app_config.dart';`

Example:
```dart
class AppConfig {
  static const String syncfusionLicenseKey = 'your-actual-key';
  static const String apiEndpoint = 'https://api.example.com';
  static const String defaultServer = 'demo.signalk.org';
}
```

## Important Notes

- **Never commit `app_config.dart`** - it's in `.gitignore`
- **Always update `app_config.example.dart`** when adding new config values
- **Share config values securely** (e.g., password manager, encrypted chat)
