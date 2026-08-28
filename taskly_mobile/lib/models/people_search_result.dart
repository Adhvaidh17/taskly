import 'contact_match.dart';

class DeviceTasklyContact {
  const DeviceTasklyContact({
    required this.match,
    required this.deviceName,
    required this.devicePhone,
  });

  final ContactMatch match;
  final String deviceName;
  final String devicePhone;

  int get profileId => match.user.id;
}
