import 'user.dart';

class ContactMatch {
  const ContactMatch({required this.user, required this.matchedBy});

  final AppUser user;
  final String matchedBy;

  factory ContactMatch.fromJson(Map<String, dynamic> json) => ContactMatch(
        user: AppUser.fromJson(json),
        matchedBy: '${json['matched_by'] ?? 'phone'}',
      );
}
