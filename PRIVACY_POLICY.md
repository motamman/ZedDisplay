# Privacy Policy for ZedDisplay

**Last updated: December 6, 2025**

## Overview

ZedDisplay is a marine navigation display application that connects to SignalK servers on your vessel's local network. This privacy policy explains how the app handles your data.

## Data Collection

**ZedDisplay does NOT collect, store, or transmit any personal data to external servers.**

All data processed by ZedDisplay remains on your local network between your devices and your SignalK server.

## Permissions

### Microphone Access (RECORD_AUDIO)

ZedDisplay requests microphone access for the **crew voice intercom feature**. This feature allows crew members to communicate via push-to-talk voice transmission over your boat's local network.

- Audio is transmitted **directly between devices** on your local network using WebRTC peer-to-peer connections
- Audio is transmitted in real-time only while the push-to-talk button is held
- Audio is **NOT recorded or stored** on any device
- Audio is **NOT transmitted to any external servers**
- Audio transmission occurs only over your vessel's local network

### Network Access (INTERNET)

Network access is required to:
- Connect to your SignalK server on the local network
- Establish WebRTC connections for voice intercom between crew devices

### Other Permissions

- **WAKE_LOCK**: Keeps the screen on while connected to prevent disconnections
- **FOREGROUND_SERVICE**: Maintains SignalK connection when the app is in the background
- **POST_NOTIFICATIONS**: Displays SignalK alarm and notification alerts

## Local Storage

ZedDisplay stores the following data locally on your device:
- SignalK server connection settings
- Dashboard layouts and tool configurations
- Crew profile (name, role) for the messaging system
- Cached messages and shared files for offline access

This data is stored only on your device and is not transmitted externally.

## Third-Party Services

ZedDisplay does not use any third-party analytics, advertising, or tracking services.

## Data Sharing

ZedDisplay does not share any data with third parties. All communication occurs exclusively between devices on your local network and your SignalK server.

## Children's Privacy

ZedDisplay does not knowingly collect any personal information from children.

## Changes to This Policy

We may update this privacy policy from time to time. Any changes will be reflected in the "Last updated" date above.

## Contact

If you have questions about this privacy policy, please contact:

**Zennora**
- GitHub: https://github.com/motamman/ZedDisplay
- Email: maurice@zennora.sv

## Open Source

ZedDisplay is open source software. You can review the source code to verify our privacy practices.
