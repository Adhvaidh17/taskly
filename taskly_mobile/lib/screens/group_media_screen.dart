import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_theme.dart';
import '../models/channel.dart';
import '../models/message.dart';
import '../providers/chat_provider.dart';

class GroupMediaScreen extends StatefulWidget {
  const GroupMediaScreen({super.key, required this.conversation, this.initialIndex = 0});
  final ConversationItem conversation;
  final int initialIndex;
  @override State<GroupMediaScreen> createState() => _GroupMediaScreenState();
}

class _GroupMediaScreenState extends State<GroupMediaScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final Map<String, List<Map<String, dynamic>>> _rows = {};
  final Set<String> _loading = {};
  final Map<String, String> _errors = {};

  @override void initState() { super.initState(); _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialIndex); for (final kind in const ['media','documents','links']) { _load(kind); } }
  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load(String kind) async {
    if (_loading.contains(kind)) return;
    _loading.add(kind); _errors.remove(kind); if (mounted) setState(() {});
    try {
      final backend = context.read<ChatProvider>().backend;
      _rows[kind] = await backend.groupSharedContent(widget.conversation.channelId, kind: kind, limit: 100);
    } catch (error) {
      _errors[kind] = '$error';
    } finally { _loading.remove(kind); if (mounted) setState(() {}); }
  }

  Widget _state(String kind, Widget content) {
    final rows = _rows[kind] ?? const [];
    if (_loading.contains(kind) && rows.isEmpty) return const Center(child: CircularProgressIndicator());
    final error = _errors[kind];
    if (error != null && rows.isEmpty) return _ErrorState(message: error, onRetry: () => _load(kind));
    return content;
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Media, links and docs'), bottom: TabBar(controller: _tabs, tabs: const [Tab(text:'Media'),Tab(text:'Docs'),Tab(text:'Links')])),
    body: TabBarView(controller: _tabs, children: [_state('media', _mediaGrid()), _state('documents', _documents()), _state('links', _links())]),
  );

  Widget _mediaGrid() {
    final rows = _rows['media'] ?? const []; if (rows.isEmpty) return const _EmptyState(label:'No media shared yet');
    final provider = context.read<ChatProvider>(); final profileId = provider.currentProfileId ?? 0;
    return GridView.builder(padding: const EdgeInsets.all(2), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,crossAxisSpacing:2,mainAxisSpacing:2), itemCount:rows.length, itemBuilder:(context,index){
      final message=MessageItem.fromJson(rows[index],currentProfileId:profileId); final isVideo=(message.attachmentMimeType??'').startsWith('video/');
      return FutureBuilder<String?>(future:provider.ensureMessageLocal(message),builder:(context,snapshot){ final path=snapshot.data; return InkWell(onTap:() async { try { await provider.openMessageAttachment(message); } catch(error){ if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$error'))); } },child:Container(color:context.taskly.panelSoft,child:Stack(fit:StackFit.expand,children:[if(path!=null&&!isVideo&&File(path).existsSync()) Image.file(File(path),fit:BoxFit.cover,cacheWidth:420) else Icon(isVideo?Icons.play_circle_fill_rounded:Icons.photo_outlined,size:34,color:context.taskly.textFaint),if(isVideo) const Center(child:Icon(Icons.play_circle_fill_rounded,color:Colors.white,size:34))]))); });
    });
  }

  Widget _documents() { final rows=_rows['documents']??const[]; if(rows.isEmpty)return const _EmptyState(label:'No documents shared yet'); final provider=context.watch<ChatProvider>(); final profileId=provider.currentProfileId??0; return ListView.separated(itemCount:rows.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,index){final message=MessageItem.fromJson(rows[index],currentProfileId:profileId);final saved=provider.localAttachmentPaths[message.id]!=null;return ListTile(leading:const CircleAvatar(child:Icon(Icons.insert_drive_file_outlined)),title:Text(message.attachmentName??message.body,maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text(message.sender.name),trailing:Icon(saved?Icons.open_in_new_rounded:Icons.download_rounded),onTap:()async{try{await provider.openMessageAttachment(message);if(mounted)setState((){});}catch(error){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$error')));}});}); }

  Widget _links() { final rows=_rows['links']??const[]; final links=<String>[]; for(final row in rows){links.addAll(_allLinks('${row['body']??''}'));} if(links.isEmpty)return const _EmptyState(label:'No links shared yet'); return ListView.separated(itemCount:links.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,index){final raw=links[index];final normalized=raw.startsWith('www.')?'https://$raw':raw;return ListTile(leading:const CircleAvatar(child:Icon(Icons.link_rounded)),title:Text(raw,maxLines:2,overflow:TextOverflow.ellipsis),onTap:()async{final uri=Uri.tryParse(normalized);if(uri!=null){try{await launchUrl(uri,mode:LaunchMode.externalApplication);}catch(error){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$error')));}}}});}); }
}

class _EmptyState extends StatelessWidget { const _EmptyState({required this.label}); final String label; @override Widget build(BuildContext context)=>Center(child:Text(label,style:TextStyle(color:context.taskly.textMuted))); }
class _ErrorState extends StatelessWidget { const _ErrorState({required this.message,required this.onRetry}); final String message; final VoidCallback onRetry; @override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off_rounded,size:46),const SizedBox(height:12),Text(message,textAlign:TextAlign.center),const SizedBox(height:12),FilledButton.icon(onPressed:onRetry,icon:const Icon(Icons.refresh),label:const Text('Retry'))]))); }
Iterable<String> _allLinks(String text)=>RegExp(r'(?:(?:https?://)|(?:www\.))[^\s<>()]+',caseSensitive:false).allMatches(text).map((m)=>m.group(0)!).where((url)=>url.isNotEmpty);
