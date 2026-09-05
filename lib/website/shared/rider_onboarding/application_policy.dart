String? riderApplicationError(Map<String, String> fields) {
  const required = {
    'fullName': 'Enter your full name.',
    'phoneNumber': 'Enter your phone number.',
    'postcode': 'Enter your postcode.',
    'homeAddress': 'Enter your address.',
    'vehicleType': 'Choose Motorbike, Car or Van.',
    'vehicleRegistration': 'Enter your vehicle registration.'
  };
  for (final field in required.entries) {
    if ((fields[field.key] ?? '').trim().isEmpty) return field.value;
  }
  if (!const {'motorbike', 'car', 'van'}
      .contains(fields['vehicleType']!.trim().toLowerCase())) {
    return required['vehicleType'];
  }
  return null;
}

String riderDocumentKey(String type) {
  final token =
      type.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return const {
        'driving_license': 'driving_licence',
        'passport': 'identity',
        'vehicle_documents': 'registration_v5c',
        'v5c': 'registration_v5c',
        'vehicle_registration': 'registration_v5c',
        'vehicle_insurance': 'insurance'
      }[token] ??
      token;
}
