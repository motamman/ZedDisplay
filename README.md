# Zed Display - SignalK Marine Data Visualization

A modern Flutter-based Android app for displaying SignalK marine data with beautiful gauges, charts, and real-time visualization.

## Features

### Current Implementation (v1.0)

- **Real-time SignalK Connection**: WebSocket-based connection to any SignalK server
- **Beautiful Gauges**: Custom-painted radial gauges for displaying numeric data
- **Compass Display**: Dedicated compass widget for heading/bearing
- **Live Dashboard**: Real-time updates of marine data including:
  - Speed Over Ground (SOG)
  - Speed Through Water (STW)
  - Heading (True)
  - Wind Speed
  - Depth
  - Battery Voltage
- **Connection Management**: Easy server configuration with secure/non-secure options
- **Dark Mode Support**: Automatic light/dark theme based on system settings

### Upcoming Features

- Line charts for historical data trends
- Customizable dashboard layouts
- PUT requests for sending commands to SignalK
- Switches and dials for interactive controls
- Multiple dashboard pages
- Data path selection and configuration
- Alerts and notifications
- Offline data caching

## Prerequisites

Before you begin, make sure you have the following installed:

1. **Flutter SDK** (3.0.0 or higher)
   - Download from: https://docs.flutter.dev/get-started/install
   - Follow the installation guide for your platform (macOS, Windows, Linux)

2. **VS Code** with Flutter Extension
   - Install VS Code: https://code.visualstudio.com/
   - Install Flutter extension from the VS Code marketplace

3. **Android Setup**:
   - Android Studio (for Android SDK and emulator) OR
   - Android SDK command-line tools
   - An Android device or emulator

## Quick Start

### 1. Verify Flutter Installation

```bash
flutter doctor
```

Make sure all checkmarks are green, especially for Flutter and Android toolchain.

### 2. Get Dependencies

```bash
flutter pub get
```

### 3. Run the App

**On an emulator:**
```bash
flutter run
```

**On a physical device:**
- Enable Developer Options and USB Debugging on your Android device
- Connect via USB
- Run `flutter devices` to verify the device is detected
- Run `flutter run`

### 4. Connect to SignalK Server

The app will open to a connection screen where you can:
- Enter your SignalK server address (e.g., `192.168.1.100:3000` or `demo.signalk.org`)
- Toggle secure connection (HTTPS/WSS) if your server supports it
- Tap "Connect"

**Testing with Demo Server:**
Use `demo.signalk.org` with secure connection enabled to test with sample data.

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── models/
│   └── signalk_data.dart       # Data models for SignalK messages
├── services/
│   └── signalk_service.dart    # WebSocket client and data management
├── widgets/
│   ├── radial_gauge.dart       # Custom radial gauge widget
│   └── compass_gauge.dart      # Custom compass widget
└── screens/
    ├── connection_screen.dart  # Server connection UI
    └── dashboard_screen.dart   # Main data display dashboard
```

## Development Guide

### Understanding the Architecture

**SignalKService** (`lib/services/signalk_service.dart`):
- Handles WebSocket connection to SignalK server
- Automatically discovers the correct WebSocket endpoint
- Manages data subscriptions and real-time updates
- Provides methods to access latest data values
- Uses Provider/ChangeNotifier for state management

**Widgets** (`lib/widgets/`):
- `RadialGauge`: Customizable circular gauge using CustomPainter
- `CompassGauge`: Compass display with cardinal directions
- Both widgets update automatically when data changes

**Data Flow**:
1. SignalKService connects to server via WebSocket
2. Server sends delta updates with data changes
3. Service parses updates and stores latest values
4. Widgets listen to service changes via Provider
5. UI rebuilds automatically with new data

### Adding New Gauges

To display additional SignalK data paths:

1. Find the SignalK path you want to display (e.g., `environment.water.temperature`)
2. In `dashboard_screen.dart`, extract the value:
   ```dart
   final waterTemp = service.getNumericValue('environment.water.temperature') ?? 0.0;
   ```
3. Add a RadialGauge widget:
   ```dart
   RadialGauge(
     value: waterTemp,
     minValue: 0,
     maxValue: 40,
     label: 'Water Temp',
     unit: '°C',
     primaryColor: Colors.blue,
   )
   ```

### Customizing Gauges

The `RadialGauge` widget accepts these parameters:
- `value`: Current numeric value to display
- `minValue` / `maxValue`: Gauge range
- `label`: Text label above the value
- `unit`: Unit of measurement below the value
- `primaryColor`: Color of the gauge arc
- `divisions`: Number of tick marks (default: 10)

### Working with Units

SignalK uses SI units (meters, m/s, radians, etc.). Convert to your preferred units:

```dart
// Speed: m/s to knots
final speedKnots = speedMetersPerSecond * 1.94384;

// Heading: radians to degrees
final headingDegrees = headingRadians * 180 / 3.14159;

// Temperature: Kelvin to Celsius
final tempCelsius = tempKelvin - 273.15;
```

### Implementing PUT Requests

To send commands to SignalK (e.g., changing autopilot settings):

```dart
final service = context.read<SignalKService>();
await service.sendPutRequest('steering.autopilot.target.headingTrue', 1.57); // 90 degrees in radians
```

## Testing

### Unit Tests
```bash
flutter test
```

### Running on Different Devices

**Android Emulator:**
```bash
flutter emulators                    # List available emulators
flutter emulators --launch <id>      # Launch specific emulator
flutter run
```

**Physical Android Device:**
1. Enable USB debugging on your device
2. Connect via USB
3. Run `flutter run`

## Building for Release

### Android APK
```bash
flutter build apk --release
```
The APK will be in `build/app/outputs/flutter-apk/app-release.apk`

### Android App Bundle (for Play Store)
```bash
flutter build appbundle --release
```

## Troubleshooting

**"Connection failed"**:
- Verify SignalK server is running and accessible
- Check if you need secure connection (HTTPS/WSS)
- Try with `demo.signalk.org` to verify the app works
- Check firewall settings on your network

**"No data points received"**:
- The SignalK server may not be sending data
- Check the debug info section on the dashboard
- Verify your vessel is generating data

**Flutter issues**:
- Run `flutter clean` and then `flutter pub get`
- Try `flutter doctor` to diagnose installation issues
- Delete the `build/` directory and rebuild

**VS Code issues**:
- Make sure Flutter extension is installed
- Restart VS Code after installing Flutter
- Select the correct device from the status bar

## Next Steps & Roadmap

### Phase 1 (Current) - Basic Display
- [x] SignalK WebSocket connection
- [x] Radial gauges
- [x] Compass display
- [x] Real-time data updates

### Phase 2 - Charts & History
- [ ] Add fl_chart library integration
- [ ] Line charts for speed, depth, wind over time
- [ ] Data caching for historical views
- [ ] Time range selection

### Phase 3 - Interactivity
- [ ] PUT request implementation for controls
- [ ] Switch widgets (on/off controls)
- [ ] Dial widgets (rotary controls)
- [ ] Confirmation dialogs for critical commands

### Phase 4 - Customization
- [ ] User-configurable dashboards
- [ ] Drag-and-drop gauge placement
- [ ] Custom color themes
- [ ] Save/load dashboard layouts

### Phase 5 - Advanced Features
- [ ] Alerts and notifications
- [ ] Waypoint display
- [ ] Route visualization
- [ ] Multi-vessel support
- [ ] Offline mode with local data storage

## Resources

- **Flutter Documentation**: https://docs.flutter.dev/
- **SignalK Documentation**: https://signalk.org/
- **fl_chart Library**: https://pub.dev/packages/fl_chart
- **Provider Pattern**: https://pub.dev/packages/provider

## Contributing

This is a personal project, but suggestions and improvements are welcome! Feel free to:
- Report issues
- Suggest new features
- Submit pull requests
- Share your custom gauge designs

## License

This project is open source and available for personal and commercial use.

## Acknowledgments

- SignalK community for the excellent open standard
- Flutter team for the amazing framework
- Demo.signalk.org for providing test data
