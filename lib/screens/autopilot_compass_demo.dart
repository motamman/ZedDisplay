import 'package:flutter/material.dart';
import 'dart:async';
import '../widgets/autopilot_compass.dart';

/// Demo screen to test the autopilot compass widget
class AutopilotCompassDemo extends StatefulWidget {
  const AutopilotCompassDemo({super.key});

  @override
  State<AutopilotCompassDemo> createState() => _AutopilotCompassDemoState();
}

class _AutopilotCompassDemoState extends State<AutopilotCompassDemo> {
  double _heading = 27.0;
  double _targetHeading = 45.0;
  double? _crossTrackError = 4.0;
  bool _showTarget = true;
  bool _animateHeading = false;
  Timer? _animationTimer;

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  void _toggleAnimation() {
    setState(() {
      _animateHeading = !_animateHeading;
    });

    if (_animateHeading) {
      _animationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        setState(() {
          _heading = (_heading + 1) % 360;
        });
      });
    } else {
      _animationTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Autopilot Compass Demo'),
        backgroundColor: Colors.grey[900],
      ),
      body: Column(
        children: [
          // Compass display
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                padding: const EdgeInsets.all(16),
                child: AutopilotCompass(
                  heading: _heading,
                  targetHeading: _targetHeading,
                  crossTrackError: _crossTrackError,
                  mode: 'Mag',
                  showTarget: _showTarget,
                ),
              ),
            ),
          ),

          // Controls
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              border: Border(
                top: BorderSide(color: Colors.white24),
              ),
            ),
            child: Column(
              children: [
                // Heading controls
                Row(
                  children: [
                    const Text(
                      'Heading:',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Slider(
                        value: _heading,
                        min: 0,
                        max: 360,
                        divisions: 360,
                        label: '${_heading.toStringAsFixed(0)}°',
                        onChanged: (value) {
                          setState(() {
                            _heading = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        '${_heading.toStringAsFixed(0)}°',
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),

                // Target heading controls
                Row(
                  children: [
                    const Text(
                      'Target:',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Slider(
                        value: _targetHeading,
                        min: 0,
                        max: 360,
                        divisions: 360,
                        label: '${_targetHeading.toStringAsFixed(0)}°',
                        onChanged: (value) {
                          setState(() {
                            _targetHeading = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        '${_targetHeading.toStringAsFixed(0)}°',
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),

                // XTE controls
                Row(
                  children: [
                    const Text(
                      'XTE:',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Slider(
                        value: _crossTrackError ?? 0,
                        min: -50,
                        max: 50,
                        divisions: 100,
                        label: '${_crossTrackError?.toStringAsFixed(0)}m',
                        onChanged: (value) {
                          setState(() {
                            _crossTrackError = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        '${_crossTrackError?.toStringAsFixed(0)}m',
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Toggle buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _toggleAnimation,
                      icon: Icon(_animateHeading ? Icons.pause : Icons.play_arrow),
                      label: Text(_animateHeading ? 'Stop' : 'Animate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _animateHeading ? Colors.orange : Colors.blue,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showTarget = !_showTarget;
                        });
                      },
                      icon: Icon(_showTarget ? Icons.visibility : Icons.visibility_off),
                      label: Text(_showTarget ? 'Hide Target' : 'Show Target'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _crossTrackError = _crossTrackError == null ? 4.0 : null;
                        });
                      },
                      icon: Icon(_crossTrackError != null ? Icons.close : Icons.add),
                      label: Text(_crossTrackError != null ? 'Hide XTE' : 'Show XTE'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
