class MessageMediaTicket {
  const MessageMediaTicket({
    required this.available,
    this.url,
    this.name,
    this.mimeType,
    this.sizeBytes,
  });

  final bool available;
  final String? url;
  final String? name;
  final String? mimeType;
  final int? sizeBytes;

  factory MessageMediaTicket.fromJson(Map<String, dynamic> json) {
    return MessageMediaTicket(
      available: json['available'] == true,
      url: json['url']?.toString(),
      name: json['name']?.toString(),
      mimeType: json['mimeType']?.toString(),
      sizeBytes: json['sizeBytes'] is num
          ? (json['sizeBytes'] as num).toInt()
          : int.tryParse('${json['sizeBytes'] ?? ''}'),
    );
  }
}
