import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class IncomingSharePayload {
  const IncomingSharePayload({required this.files, required this.text});

  final List<String> files;
  final String text;

  bool get isEmpty => files.isEmpty && text.trim().isEmpty;
}

class IncomingShareService extends ChangeNotifier {
  StreamSubscription<List<SharedMediaFile>>? _subscription;
  IncomingSharePayload? _pending;
  bool _initialised = false;

  IncomingSharePayload? get pending => _pending;

  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;
    _subscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _accept,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('TASKLY_SHARE_STREAM_ERROR $error');
      },
    );
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      _accept(initial);
      await ReceiveSharingIntent.instance.reset();
    } catch (error) {
      debugPrint('TASKLY_SHARE_INITIAL_ERROR $error');
    }
  }

  void _accept(List<SharedMediaFile> media) {
    if (media.isEmpty) return;
    final files = <String>[];
    final textParts = <String>[];
    for (final item in media) {
      final path = item.path.trim();
      if (path.isEmpty) continue;
      if (item.type == SharedMediaType.text || item.type == SharedMediaType.url) {
        textParts.add(path);
      } else {
        files.add(path);
        final message = item.message?.trim() ?? '';
        if (message.isNotEmpty) textParts.add(message);
      }
    }
    final payload = IncomingSharePayload(
      files: files.toSet().toList(growable: false),
      text: textParts.toSet().join('\n').trim(),
    );
    if (payload.isEmpty) return;
    _pending = payload;
    notifyListeners();
  }

  IncomingSharePayload? consume() {
    final value = _pending;
    _pending = null;
    if (value != null) notifyListeners();
    return value;
  }

  void clear() {
    if (_pending == null) return;
    _pending = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
