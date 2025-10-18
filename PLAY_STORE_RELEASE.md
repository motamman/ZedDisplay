# Google Play Store Internal Testing Release Guide

## Current Status
- **App Name:** SignalK ZedDisplay
- **Package:** com.zennora.zed_display
- **Version:** 0.1.0+2 (Version Name: 0.1.0, Version Code: 2)

---

## Step 1: Create Upload Keystore

Run this command in your terminal to create a signing key:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload
```

You'll be prompted for:
- **Keystore password** (choose a strong password and save it securely!)
- **Key password** (can be same as keystore password)
- **Name and organization details** (fill in your details)

⚠️ **IMPORTANT:** Save your keystore and passwords securely! If you lose them, you can never update your app on Play Store.

---

## Step 2: Configure Key Properties

Edit the file `android/key.properties` with your actual values:

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=/Users/mauricetamman/upload-keystore.jks
```

Replace:
- `YOUR_KEYSTORE_PASSWORD` with the password you chose
- `YOUR_KEY_PASSWORD` with the key password
- Update the path to your keystore if you saved it elsewhere

---

## Step 3: Build Release Bundle

Clean and build the release AAB (Android App Bundle):

```bash
# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Build the release AAB
flutter build appbundle --release
```

The AAB will be created at:
```
build/app/outputs/bundle/release/app-release.aab
```

---

## Step 4: Test the Release Build (Optional but Recommended)

You can test with an APK first:

```bash
flutter build apk --release
flutter install --release -d <device-id>
```

---

## Step 5: Prepare for Play Console Upload

### Required Assets

You'll need to prepare these in the Play Console:

#### App Screenshots (Required)
- **Phone screenshots:** At least 2 (up to 8)
  - Minimum: 320px
  - Maximum: 3840px
  - Recommended: 1080 x 1920px or 1080 x 2400px

#### App Icon
- Already configured: `assets/icon.png`

#### Feature Graphic (Required for Store Listing)
- Size: 1024 x 500px
- JPG or PNG

#### Privacy Policy
- You'll need a URL to your privacy policy
- Required if your app collects user data

---

## Step 6: Upload to Google Play Console

### First Time Setup

1. **Go to Google Play Console:** https://play.google.com/console
2. **Create a new app:**
   - Click "Create app"
   - App name: **SignalK ZedDisplay**
   - Default language: English
   - App or game: App
   - Free or paid: Free (or Paid)
   - Accept declarations

### Upload the AAB

1. **Navigate to:** Production → Releases → Create new release
   - Or for internal testing: Internal testing → Create new release

2. **Upload the AAB:**
   - Click "Upload" and select `build/app/outputs/bundle/release/app-release.aab`

3. **Fill in release details:**
   - Release name: `0.1.0` (or your version)
   - Release notes:
     ```
     Initial internal testing release
     - SignalK data visualization
     - Interactive gauges and controls
     - Dashboard management
     ```

### Complete Store Listing

1. **App details:**
   - Short description (80 chars max)
   - Full description (4000 chars max)
   - App icon (already set)
   - Feature graphic (create one)
   - Screenshots (capture from your device)

2. **Categorization:**
   - App category: Tools / Navigation
   - Tags: Add relevant tags

3. **Contact details:**
   - Email address
   - Phone number (optional)
   - Website (optional)

4. **Privacy policy:**
   - Required if collecting data
   - Must be a URL

### Set Up Internal Testing

1. **Create Internal Testing Release:**
   - Go to "Internal testing" in left menu
   - Click "Create new release"
   - Upload your AAB
   - Add release notes
   - Review and roll out

2. **Add Testers:**
   - Create an email list of testers
   - Or share the opt-in URL with testers

3. **Share Test Link:**
   - Copy the testing link
   - Share with your internal testers
   - They'll need to accept the invitation and download the app

---

## Version Management

### To Update Version for Next Release

Edit `pubspec.yaml`:

```yaml
version: 0.1.1+3  # Format: major.minor.patch+buildNumber
```

- **Version Name:** 0.1.1 (user-visible)
- **Version Code:** 3 (must increment with each release)

Then rebuild:
```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

---

## Security Checklist

✅ Keystore saved in secure location (NOT in project directory)
✅ `key.properties` added to `.gitignore`
✅ Keystore passwords stored securely (password manager)
✅ Release builds configured and tested
✅ ProGuard rules configured for code optimization

---

## Troubleshooting

### "Signing key not found"
- Make sure `key.properties` has correct paths
- Check that keystore file exists at specified location

### "Upload failed - version code already exists"
- Increment the version code in `pubspec.yaml`

### "APK/AAB too large"
- Current optimizations are enabled (minify, shrink resources)
- Check that you're not including unnecessary assets

---

## Quick Command Reference

```bash
# Clean build
flutter clean && flutter pub get

# Build release AAB for Play Store
flutter build appbundle --release

# Build release APK for testing
flutter build apk --release

# Install release APK on device
flutter install --release

# Check AAB size
ls -lh build/app/outputs/bundle/release/app-release.aab

# Find connected devices
flutter devices
```

---

## Next Steps After Upload

1. **Complete all store listing sections**
2. **Add screenshots and graphics**
3. **Set up content rating questionnaire**
4. **Complete app content declarations**
5. **Submit for review** (or roll out to internal testers)

Internal testing releases are usually available within minutes!

---

## Support

If you encounter issues:
- Check the Play Console dashboard for specific errors
- Review the [Flutter deployment docs](https://docs.flutter.dev/deployment/android)
- Check Google Play Console help center

Good luck with your release! 🚀
