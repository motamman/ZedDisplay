# <img src="assets/icon.png" alt="SignalK Zed Display" width="72" height="72" style="vertical-align: middle; margin-right: 20px;"> SignalK Parquet Data Store

# ZedDisplay

A customizable SignalK marine dashboard application to display real-time vessel data with configurable tools.
 
## SignalK Dependencies
 - signalk-units-preference must me install to have base values converted. Without it many tools will not work.
 - signalk-parquet allows some tools to display historic data for selected paths. 




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
- **Radial Gauge**: Circular gauge for numeric values
- **Linear Gauge**: Horizontal/vertical bar gauge
- **Compass**: Heading display
- **Text Display**: Formatted text output

**Chart Tools**
- **Historical Chart**: Time series line charts
- **Realtime Chart**: Live updating line charts
- **Radial Bar Chart**: Circular bar charts
- **Polar Radar Chart**: Polar coordinate visualization
- **AIS Polar Chart**: AIS target display on polar radar

**Navigation Tools**
- **Wind Compass**: Wind direction and speed display
- **Autopilot**: Course control interface

**Control Tools**
- **Switch**: Toggle control
- **Slider**: Continuous value adjustment
- **Knob**: Rotary control
- **Checkbox**: Boolean toggle
- **Dropdown**: Selection control

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
![Main Dashboard](docs/screenshots/dashboard.png)
*Main dashboard with multiple gauges and instruments*

![Navigation Screen](docs/screenshots/navigation.png)
*Navigation-focused screen with compass and wind data*

![Engine Monitoring](docs/screenshots/engine.png)
*Engine monitoring screen*

### Setup & Configuration
![Dashboard Manager](docs/screenshots/dashboard-manager.png)
*Dashboard screen management*

![Tool Configuration](docs/screenshots/tool-config.png)
*Configuring a gauge tool*

![Setup Management](docs/screenshots/setup-management.png)
*Managing and sharing dashboard setups*

### Connection & Settings
![Server List](docs/screenshots/server-list.png)
*Saved server connections*

![Settings](docs/screenshots/settings.png)
*Settings screen*

![Device Registration](docs/screenshots/device-registration.png)
*SignalK device registration flow*

## Getting Started

### Prerequisites

- Flutter SDK (>=3.8.0 <4.0.0)
- Android SDK (for Android builds) or Xcode (for iOS builds)
- Access to a SignalK server (local or remote)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/ZedDisplay.git
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
   - Long-press on a screen to add tools
   - Choose a tool type (gauge, chart, compass, etc.)
   - Configure the data source and styling
   - Position it on the grid

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
    ↓
DashboardService (Data distribution)
    ↓
Tool Components (Display layer)
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

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [SignalK](https://signalk.org/) - Open source marine data standard
- [Syncfusion](https://www.syncfusion.com/flutter-widgets) - Beautiful charts and gauges
- Flutter team for an amazing framework

## Support

For questions or issues:
- Open an issue on GitHub
- Check the [SignalK documentation](https://signalk.org/documentation/)

## Roadmap

- [ ] Offline mode with cached data
- [ ] Chart playback for historical data
- [ ] Enhanced alerts and notification rules
- [ ] Weather integration (GRIB files, forecasts)
- [x] AIS target display (completed in v0.2.0+3)
- [ ] Route planning and waypoint navigation
- [ ] More chart types (bar charts, area charts)
- [ ] AI integration

---

**Built with ❤️ for the marine community**
