import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';

class ChatInfoScreen extends StatelessWidget {
  const ChatInfoScreen({super.key, required this.channelId});
  final int channelId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Chat Info')),
      body: Center(child: Text('Channel $channelId')),
    );
  }
}
