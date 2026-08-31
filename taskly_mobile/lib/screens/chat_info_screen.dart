import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../local_chat/local_chat_runtime.dart';
import '../providers/chat_provider.dart';

class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({super.key, required this.channelId});
  final int channelId;
  @override State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  bool _loading = true;
  String? _error;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      // Do not initialize live transport merely to render Chat Info.
      // ChatProvider owns the backend and local chat state.
      await context.read<ChatProvider>().loadChatInfo(widget.channelId);
      if (mounted) setState(() { _loading = false; _error = null; });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _error = '$error'; });
    }
  }

  @override Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('Chat Info')), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: () { setState(() => _loading = true); _load(); }, icon: const Icon(Icons.refresh), label: const Text('Retry'))])));
    return Scaffold(appBar: AppBar(title: const Text('Chat Info')), body: const Center(child: Text('Chat information')));
  }
}
