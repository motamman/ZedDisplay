# Assets Folder

## Required Files

### 1. App Icon
Place your app icon images in this folder:

- **icon.png** - Main app icon (1024x1024 px, PNG format)
- **icon_foreground.png** - Foreground layer for adaptive icon (1024x1024 px, PNG format with transparency)

### 2. Splash Video
- **splash.mp4** - Splash screen video (MP4 format, recommended: 1080p, under 5MB)

## Generating App Icons

After adding `icon.png` and `icon_foreground.png`, run:
```bash
flutter pub run flutter_launcher_icons
```

This will automatically generate all required icon sizes for Android.

## Notes

- The splash video plays once on app launch while connecting to the server
- The icon uses a black (#000000) background with your foreground image
- Make sure icon_foreground.png has a transparent background
- Keep the splash.mp4 file size reasonable for fast loading

## Third-Party Assets

### Weather Icons

#### Meteocons (BAS Weather Icons)
- **Location:** `weather_icons/bas_weather/`
- **Author:** [Bas Milius](https://bas.dev)
- **Source:** https://github.com/basmilius/weather-icons
- **License:** MIT License
- **Copyright:** (c) 2020-2021 Bas Milius

Meteocons is a free-to-use set of animated SVG weather icons. Used for displaying weather conditions in the forecast spinner when receiving WMO weather codes from OpenMeteo via the SignalK Weather API.

#### WMO Code Mapping
The mapping from WMO weather interpretation codes to Meteocons icons is based on:
- **Source:** https://gist.github.com/stellasphere/9490c195ed2b53c707087c8c2db4ec0c
- **Author:** stellasphere
