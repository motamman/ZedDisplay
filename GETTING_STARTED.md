# Getting Started with Zed Display

This guide will help you set up your development environment and run the app for the first time.

## Step 1: Install Flutter

### macOS
```bash
# Download Flutter SDK
cd ~/development
git clone https://github.com/flutter/flutter.git -b stable

# Add Flutter to your PATH (add to ~/.zshrc or ~/.bash_profile)
export PATH="$PATH:`pwd`/flutter/bin"

# Verify installation
flutter doctor
```

### Windows
1. Download Flutter SDK from https://docs.flutter.dev/get-started/install/windows
2. Extract to `C:\src\flutter`
3. Add `C:\src\flutter\bin` to your PATH
4. Run `flutter doctor` in PowerShell

### Linux
```bash
# Download Flutter SDK
cd ~/development
git clone https://github.com/flutter/flutter.git -b stable

# Add to PATH (add to ~/.bashrc)
export PATH="$PATH:$HOME/development/flutter/bin"

# Install dependencies
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev

# Verify installation
flutter doctor
```

## Step 2: Install VS Code and Extensions

1. Download and install VS Code from https://code.visualstudio.com/
2. Open VS Code
3. Install the Flutter extension:
   - Press `Cmd+Shift+X` (macOS) or `Ctrl+Shift+X` (Windows/Linux)
   - Search for "Flutter"
   - Click "Install" on the Flutter extension by Dart Code

## Step 3: Set Up Android Development

### Install Android Studio (Easiest)
1. Download Android Studio from https://developer.android.com/studio
2. During installation, select "Android SDK", "Android SDK Platform", and "Android Virtual Device"
3. Launch Android Studio
4. Go to Tools → SDK Manager
5. Install:
   - Android SDK Platform 33 or higher
   - Android SDK Build-Tools
   - Android SDK Command-line Tools

### Accept Android Licenses
```bash
flutter doctor --android-licenses
```
Press 'y' to accept all licenses.

## Step 4: Set Up an Android Emulator

### Option A: Using Android Studio
1. Open Android Studio
2. Click "More Actions" → "Virtual Device Manager"
3. Click "Create Device"
4. Select a device (e.g., Pixel 6)
5. Select a system image (e.g., API 33 - Android 13)
6. Click "Finish"

### Option B: Using Command Line
```bash
# List available devices
flutter emulators

# Create a new emulator
flutter emulators --create

# Launch emulator
flutter emulators --launch <emulator_id>
```

## Step 5: Get Project Dependencies

```bash
cd /path/to/ZedDisplay
flutter pub get
```

## Step 6: Run the App

### In VS Code
1. Open the ZedDisplay folder in VS Code
2. Connect your Android device or start an emulator
3. Press `F5` or click "Run" → "Start Debugging"
4. Select your device from the dropdown

### From Command Line
```bash
# List available devices
flutter devices

# Run on the first available device
flutter run

# Run on a specific device
flutter run -d <device_id>
```

## Step 7: Connect to SignalK

When the app launches:

1. You'll see a connection screen
2. For testing, enter: `demo.signalk.org`
3. Enable "Use Secure Connection"
4. Tap "Connect"
5. You should see live data from the demo server!

### Using Your Own SignalK Server

1. Make sure your SignalK server is running
2. Find your server's IP address (e.g., `192.168.1.100:3000`)
3. Enter the address in the app
4. Choose secure connection based on your server setup
5. Tap "Connect"

## Troubleshooting

### "flutter: command not found"
- Make sure you added Flutter to your PATH
- Restart your terminal/VS Code
- Run `source ~/.zshrc` (macOS) or `source ~/.bashrc` (Linux)

### "No devices found"
- Make sure an emulator is running or device is connected
- Run `flutter doctor` to check device connectivity
- Try `adb devices` to verify Android device detection

### "Android licenses not accepted"
- Run `flutter doctor --android-licenses`
- Accept all licenses

### "Unable to locate Android SDK"
- Set ANDROID_HOME environment variable
- Point it to your Android SDK location (usually `~/Library/Android/sdk` on macOS)

### App won't connect to SignalK
- Try demo.signalk.org first to verify the app works
- Check your SignalK server is running and accessible
- Verify you're using the correct protocol (http vs https)
- Check firewall settings

## Next Steps

Once you have the app running:

1. Explore the code in `lib/` directory
2. Read the main README.md for architecture details
3. Try modifying a gauge in `dashboard_screen.dart`
4. Add a new SignalK data path
5. Customize colors and styles

## Useful Commands

```bash
# Check Flutter installation
flutter doctor -v

# Get dependencies
flutter pub get

# Run the app
flutter run

# Run with hot reload
flutter run --hot

# Build release APK
flutter build apk --release

# Format all Dart files
flutter format .

# Analyze code for issues
flutter analyze

# Run tests
flutter test

# Clean build cache
flutter clean
```

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Flutter Cookbook](https://docs.flutter.dev/cookbook)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [SignalK Documentation](https://signalk.org/documentation/)

## Getting Help

If you run into issues:

1. Run `flutter doctor -v` and check for any problems
2. Try `flutter clean` and `flutter pub get`
3. Restart VS Code
4. Check the Flutter GitHub issues
5. Ask in Flutter Discord or Stack Overflow

Happy coding!
