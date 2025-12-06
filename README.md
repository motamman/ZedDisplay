# <img src="assets/icon.png" alt="ZedDisplay" width="72" height="72" style="vertical-align: middle; margin-right: 20px;"> ZedDisplay

A customizable SignalK marine dashboard application to display real-time vessel data with configurable tools.
 
## SignalK Dependencies

### Required
- **signalk-units-preference**: Must be installed to have base values converted. Without it many tools will not work.

### Optional
- **signalk-derived-data**: Provides computed values like true wind, VMG, and other derived navigational data
- **signalk-parquet**: Allows some tools to display historic data for selected paths
- **signalk-rpi-monitor**: Required for RPi Monitor tool (CPU, GPU temperature, memory, storage monitoring)
- **signalk-rpi-uptime**: Required for system uptime display in RPi Monitor tool
- **signalk-weatherflow-api**: Required for WeatherFlow Forecast tool (weather data from Tempest stations) 




## Features

### 🚢 Real-Time Marine Data Display
- Connect to any SignalK server (local or remote)
- Real-time data streaming via WebSocket
- Support for secure (HTTPS/WSS) and standard connections
- Automatic reconnection on network changes

### 📊 Customizable Dashboard
- Multiple dashboard screens with custom layouts
- Drag-and-drop tool placement
- Grid-based responsive layout

### 🎨 Tool Library

**Display Tools**
- **Radial Gauge**: Circular gauge with arc display for numeric values
- **Linear Gauge**: Horizontal or vertical bar gauge for numeric values
- **Compass Gauge**: Circular compass display for heading/bearing values (supports up to 4 needles)
  - Compare multiple headings on one display (heading, COG, autopilot target, etc.)
  - Multiple styles: classic, arc, minimal, marine
  - Custom labels that stay horizontal for easy reading
- **Text Display**: Large numeric value display with label and unit
  - Smart lat/long formatting (auto-detects and formats as degrees/minutes/seconds)
  - Object value support (displays Map properties as key-value pairs)
- **WeatherFlow Forecast**: Weather forecast from WeatherFlow Tempest station
  - Current conditions (temperature, humidity, pressure, wind)
  - Hourly forecast with weather icons, temperature, precipitation probability
  - Wind direction arrows and speed for each forecast hour
  - Configurable hours to display (up to 72 hours)
  - Requires signalk-weatherflow-api plugin

**Chart Tools**
- **Historical Chart**: Line chart showing historical data for up to 3 paths
- **Real-Time Chart**: Live spline chart showing real-time data for up to 3 paths
- **Radial Bar Chart**: Circular chart displaying up to 4 values as concentric rings
- **Polar Radar Chart**: Polar chart showing magnitude vs angle with area fill (e.g., wind speed/direction)
- **AIS Polar Chart**: Display nearby AIS vessels on polar chart relative to own position

**Navigation Tools**
- **Wind Compass**: Advanced autopilot-style compass with multiple sailing modes
  - **Target AWA Mode**: Performance steering with configurable target angles and tolerance zones
  - **Laylines Mode**: True navigation laylines for upwind waypoint navigation with "can fetch" indicators
  - **VMG Mode**: Real-time Velocity Made Good with polar-based optimization
  - Gradiated sailing zones (red/green) showing optimal sailing angles
  - Dynamic target AWA adjustment based on wind speed and polar data
  - Tap display to cycle between modes
  - Shows heading (true/magnetic), wind direction (true/apparent), SOG, and COG
- **Autopilot**: Full autopilot control with compass display, mode selection, and tacking
- **Attitude Indicator**: Aircraft-style artificial horizon display
  - Shows vessel pitch and roll in real-time
  - Configurable color scheme
  - Visual horizon line with degree markings
- **GNSS Status**: GPS/GNSS satellite and fix quality display
  - Fix type indicator (No Fix, 2D, 3D, GNSS, DGNSS, RTK Float, RTK Fixed)
  - Satellite count and signal quality
  - Horizontal/vertical dilution of precision (HDOP/VDOP)
  - Data age indicator (LIVE/stale status)
  - Detailed satellite information (PRN, elevation, azimuth, SNR)

**Control Tools**
- **Switch**: Toggle switch for boolean SignalK paths with PUT support
- **Slider**: Slider control for sending numeric values to SignalK paths
- **Knob**: Rotary knob control for sending numeric values to SignalK paths
- **Checkbox**: Checkbox for boolean SignalK paths with PUT support
- **Dropdown**: Dropdown selector for sending numeric values to SignalK paths

**System Tools**
- **Server Status**: Real-time SignalK server monitoring and management
  - Live server statistics (uptime, delta rate, connected clients, available paths)
  - Per-provider statistics with delta rates
  - Plugin management (view all plugins, enable/disable with tap)
  - Webapp listing with versions
  - Server restart functionality
  - Auto-updates every 5 seconds
- **RPi Monitor**: Raspberry Pi system health monitoring
  - CPU utilization (overall and per-core)
  - CPU and GPU temperature with color-coded warnings
  - Memory and storage utilization
  - System uptime display
  - Requires signalk-rpi-monitor and signalk-rpi-uptime plugins

### 🔧 Tool Management
- Create and save custom tool configurations
- Import/export tool definitions
- Tool library with search and filtering
- Reusable tools across multiple screens

### 💾 Setup Management & Sharing
- Save multiple dashboard setups
- Switch between setups instantly
- Export setups as JSON files
- Import shared setups from other users
- Perfect for different boat configurations or conditions

### 🔐 Secure Authentication
- SignalK OAuth2 authentication flow
- Device registration and approval
- Secure token storage
- Multiple server support

### 🌓 Modern UI/UX
- Material Design 3
- Dark and light themes
- Smooth animations and transitions
- Responsive layout for phones and tablets

## Screenshots

### Dashboard Views
![Main Dashboard](docs/screenshots/generalGauges.jpg)
*Main dashboard with multiple gauges and instruments*

![Navigation Screen](docs/screenshots/windCompass.jpg)
*Navigation-focused screen with compass and wind data*

![Autopilot Controller](docs/screenshots/autoPilot.jpg)
*Autopilot with wind and route support*

![AiS Monitoring](docs/screenshots/AISdisplay.jpg)
*AIS and vessel tracking*


### Setup & Configuration
![Dashboard Manager](docs/screenshots/setup.jpg)
*Dashboard screen management*

![Tool Configuration](docs/screenshots/editScreen.jpg)
*Configuring a gauge tool*

![Setup Management](docs/screenshots/addTool.jpg)
*Managing and sharing dashboard setups*

![SignalK Monitor](docs/screenshots/skmanager.jpg)
*Basic server and plugin monitor and manager*

## Getting Started

### Prerequisites

- Flutter SDK (>=3.8.0 <4.0.0)
- Android SDK (for Android builds) or Xcode (for iOS builds)
- Access to a SignalK server (local or remote)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/motamman/ZedDisplay.git
   cd ZedDisplay
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate code**
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Run the app**
   ```bash
   flutter run
   ```

### First Time Setup

1. Launch the app
2. Add your SignalK server connection:
   - Enter server URL (e.g., `192.168.1.100:3000` or `demo.signalk.org`)
   - Choose secure connection if using HTTPS/WSS
   - Give it a friendly name
3. Approve the device in your SignalK server's Admin UI
4. Start customizing your dashboard!

## Usage

### Creating Your First Dashboard

1. **Connect to your SignalK server**
   - Tap "Add Connection" on the connection screen
   - Enter your server details and connect

2. **Add Dashboard Screens**
   - Open the Dashboard Manager (☰ menu)
   - Tap "+" to add a new screen
   - Give it a name (e.g., "Navigation", "Engine")

3. **Add Tools to Your Screen**
   - Tap the "+" button to add tools
   - Choose a tool type (gauge, chart, compass, etc.)
   - Configure the data source and styling
   - Tool automatically places on the screen (can be moved/resized in edit mode)

4. **Save Your Setup**
   - Go to Settings → Dashboard Setups
   - Tap "Save Current"
   - Give your setup a name

### Sharing Setups

1. **Export a Setup**
   - Settings → Dashboard Setups → Manage Setups
   - Select your setup and tap "Share"
   - Share the JSON file via your preferred method

2. **Import a Setup**
   - Settings → Dashboard Setups → Manage Setups
   - Tap the import icon (📤)
   - Choose "Browse File" or "Paste JSON"
   - Decide whether to switch to it immediately

### Switching Between Setups

Perfect for different scenarios:
- **Sailing Mode**: Wind instruments, compass, speed
- **Motorsailing Mode**: Engine gauges, fuel, temperature
- **Anchoring Mode**: Depth, position, battery status

Simply go to Settings → Dashboard Setups and tap the setup you want to activate!

## Project Structure

```
lib/
├── config/           # App configuration
├── models/           # Data models
│   ├── dashboard_layout.dart
│   ├── dashboard_setup.dart
│   ├── tool.dart
│   └── server_connection.dart
├── screens/          # App screens
│   ├── splash_screen.dart
│   ├── server_list_screen.dart
│   ├── connection_screen.dart
│   ├── dashboard_manager_screen.dart
│   ├── settings_screen.dart
│   └── setup_management_screen.dart
├── services/         # Business logic
│   ├── signalk_service.dart
│   ├── storage_service.dart
│   ├── dashboard_service.dart
│   ├── tool_service.dart
│   ├── setup_service.dart
│   └── auth_service.dart
├── widgets/          # UI components
│   ├── compass_gauge.dart
│   ├── radial_gauge.dart
│   ├── linear_gauge.dart
│   └── tools/       # Tool implementations
└── main.dart
```

## Architecture

### Data Flow
```
SignalK Server (WebSocket)
    ↓
SignalKService (WebSocket handler)
    ├── DataCacheManager (TTL-based caching & pruning)
    ├── ConversionManager (Unit conversions)
    ├── NotificationManager (Alert processing)
    └── AISManager (Vessel tracking)
    ↓
DashboardService (Data distribution)
    ↓
Tool Components (Display layer)
    └── Tool Configurators (Strategy pattern)
```

### Storage
- Local persistent storage for connections, dashboards, tools, setups, and auth tokens
- JSON serialization for import/export

### State Management
- **Provider**: State management and dependency injection
- **ChangeNotifier**: Reactive updates across the app

## Technologies Used

- **Flutter**: Cross-platform UI framework
- **Syncfusion**: Gauges and charts library
- **Provider**: State management
- **SignalK**: Marine data protocol
- **WebSocket**: Real-time data streaming

## Development

### Running Tests
```bash
flutter test
```

### Building for Release

**Android:**
```bash
flutter build apk --release
```

**iOS:**
```bash
flutter build ios --release
```

### Code Generation
When adding new models with JSON serialization:
```bash
dart run build_runner build --delete-conflicting-outputs
```

## Configuration

The app includes a configuration system for sensitive data (see `CONFIG_SETUP.md`), though it's currently not required. This infrastructure is ready for future use with API keys or other configuration values.

## Developer Documentation

### Creating Custom Tools
See the comprehensive guide: [`docs/public/creating-new-tools-guide.md`](docs/public/creating-new-tools-guide.md)

This 900+ line guide covers:
- Tool architecture and the Strategy pattern
- Step-by-step tool creation (with examples)
- Tool configurators and the configuration system
- Best practices and testing
- Troubleshooting common issues

Perfect for developers wanting to add new tool types to ZedDisplay!

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For questions or issues:
- Open an issue on GitHub
- Check the [SignalK documentation](https://signalk.org/documentation/)

## Roadmap

### General Features
- [ ] Offline mode with cached data
- [ ] Chart playback for historical data
- [ ] Enhanced alerts and notification rules
- [ ] Weather integration (GRIB files, forecasts)
- [x] AIS target display (completed in v0.2.0+3)
- [ ] Route planning and waypoint navigation
- [ ] More chart types (bar charts, area charts)
- [ ] AI integration
- [ ] AIS collision avoidance using `vessels.<uuid>.navigation.closestApproach` (CPA/TCPA)
- [ ] AIS collision alerts using `notifications.danger.collision` (requires collision-detector plugin)
- [x] Weather forecast tool (completed - WeatherFlow Tempest integration)
- [x] Raspberry Pi health monitoring tool (completed - CPU, memory, temperature, uptime monitoring)
- [ ] Manage overflows with dynamic sizing (improve responsive layout across all screen sizes)

### Wind Compass Improvements
- [x] Target AWA mode with performance zones (completed)
- [x] True laylines for waypoint navigation (completed)
- [x] VMG optimization with basic polar data (completed)
- [ ] Custom polar data upload
- [ ] Downwind polar angles
- [ ] VMG optimization for reaching/running
- [ ] Polar curve visualization

---


