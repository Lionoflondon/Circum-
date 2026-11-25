bool rothCentralStagingEnabledFor({
  required String firebaseProjectId,
  required bool enabled,
  required String configuredProjectId,
}) =>
    enabled &&
    configuredProjectId.isNotEmpty &&
    configuredProjectId != 'circum-2797c' &&
    RegExp(
      r'(^|[-_])(stage|staging|stg|dev|test)([-_]|$)',
      caseSensitive: false,
    ).hasMatch(configuredProjectId) &&
    firebaseProjectId == configuredProjectId;
