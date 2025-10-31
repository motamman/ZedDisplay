/// Models for SignalK V2 Autopilot API
///
/// The V2 API supports multiple autopilot instances, separate engage/disengage,
/// and enhanced capabilities like dodge mode and gybe support.

/// V2 API autopilot instance
class AutopilotInstance {
  final String id;
  final String name;
  final String provider;
  final bool isDefault;
  final Map<String, String> endpoints;

  AutopilotInstance({
    required this.id,
    required this.name,
    required this.provider,
    this.isDefault = false,
    required this.endpoints,
  });

  factory AutopilotInstance.fromJson(Map<String, dynamic> json) {
    return AutopilotInstance(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'],
      provider: json['provider'] as String? ?? 'unknown',
      isDefault: json['default'] as bool? ?? false,
      endpoints: Map<String, String>.from(json['endpoints'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'provider': provider,
      'default': isDefault,
      'endpoints': endpoints,
    };
  }
}

/// V2 API autopilot capabilities and state
class AutopilotInfo {
  final AutopilotOptions options;
  final String? mode;
  final String? state;
  final bool engaged;
  final double? target;

  AutopilotInfo({
    required this.options,
    this.mode,
    this.state,
    required this.engaged,
    this.target,
  });

  factory AutopilotInfo.fromJson(Map<String, dynamic> json) {
    return AutopilotInfo(
      options: AutopilotOptions.fromJson(json['options'] ?? {}),
      mode: json['mode'] as String?,
      state: json['state'] as String?,
      engaged: json['engaged'] as bool? ?? false,
      target: (json['target'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'options': options.toJson(),
      'mode': mode,
      'state': state,
      'engaged': engaged,
      'target': target,
    };
  }
}

/// Available modes and states for autopilot
class AutopilotOptions {
  final List<AutopilotState> states;
  final List<String> modes;
  final List<String> actions;

  AutopilotOptions({
    required this.states,
    required this.modes,
    this.actions = const [],
  });

  factory AutopilotOptions.fromJson(Map<String, dynamic> json) {
    return AutopilotOptions(
      states: (json['states'] as List?)
              ?.map((s) => AutopilotState.fromJson(s))
              .toList() ??
          [],
      modes: (json['modes'] as List?)?.map((m) => m.toString()).toList() ?? [],
      actions:
          (json['actions'] as List?)?.map((a) => a.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'states': states.map((s) => s.toJson()).toList(),
      'modes': modes,
      'actions': actions,
    };
  }
}

/// Autopilot state definition
class AutopilotState {
  final String name;
  final bool engaged;

  AutopilotState({
    required this.name,
    required this.engaged,
  });

  factory AutopilotState.fromJson(dynamic json) {
    if (json is String) {
      // Simple string format - determine engaged from name
      return AutopilotState(
        name: json,
        engaged: json.toLowerCase() != 'standby',
      );
    }
    // Object format with explicit engaged field
    return AutopilotState(
      name: json['name'] as String,
      engaged: json['engaged'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'engaged': engaged,
    };
  }
}

/// V2 API response wrapper
class AutopilotV2Response {
  final String status;
  final String? message;
  final Map<String, dynamic>? data;

  AutopilotV2Response({
    required this.status,
    this.message,
    this.data,
  });

  factory AutopilotV2Response.fromJson(Map<String, dynamic> json) {
    return AutopilotV2Response(
      status: json['status'] as String? ?? 'error',
      message: json['message'] as String?,
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  bool get isSuccess => status == 'success';

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'message': message,
      'data': data,
    };
  }
}
