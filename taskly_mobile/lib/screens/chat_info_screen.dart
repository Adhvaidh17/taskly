import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../local_chat/local_chat_runtime.dart';
import '../providers/chat_provider.dart';

class ChatInfoScreen extends StatelessWidget {
  const ChatInfoScreen({super.key, required this.channelId});
  final int channelId;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ChatProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Chat Info')),
      body: FutureBuilder<void>(
        future: _prepareLocalOnly(provider),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snapshot.error}', textAlign: TextAlign.center)));
          }
          return Center(child: Text('Channel $channelId'));
        },
      ),
    );
  }

  Future<void> _prepareLocalOnly(ChatProvider provider) async {
    final client = provider.backend.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    // Open local state without requiring the live transport to be connected.
    final runtime = LocalChatRuntime.instance;
    await runtime.initialize(client);
  }
}
