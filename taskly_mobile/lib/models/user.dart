class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.phoneCountryIso,
    this.avatarUrl,
    this.about,
    this.role,
  });

  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? phoneCountryIso;
  final String? avatarUrl;
  final String? about;
  final String? role;

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: asInt(json['id']),
        name: '${json['name'] ?? 'Unknown'}',
        email: '${json['email'] ?? ''}',
        phone: json['phone'] as String?,
        phoneCountryIso: json['phone_country_iso'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        about: json['about'] as String?,
        role: json['role'] as String?,
      );
}

int asInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
