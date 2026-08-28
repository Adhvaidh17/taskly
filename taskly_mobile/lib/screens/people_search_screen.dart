import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../config/app_config.dart';
import '../models/contact_match.dart';
import '../models/people_search_result.dart';
import '../providers/chat_provider.dart';
import '../providers/contact_provider.dart';
import '../widgets/country_phone_field.dart';
import 'chat_room_screen.dart';

enum PeopleSearchMode { newChat, addToGroup }

class PeopleSearchScreen extends StatefulWidget {
  const PeopleSearchScreen({
    super.key,
    required this.mode,
    this.workspaceId,
    this.channelId,
    this.excludedProfileIds = const <int>{},
  });

  final PeopleSearchMode mode;
  final int? workspaceId;
  final int? channelId;
  final Set<int> excludedProfileIds;

  @override
  State<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends State<PeopleSearchScreen> {
  final _search = TextEditingController();
  String _countryIso = AppConfig.defaultCountryIso;
  Timer? _debounce;
  int _searchVersion = 0;
  int? _busyProfileId;

  bool get _addingToGroup => widget.mode == PeopleSearchMode.addToGroup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactProvider>().sync();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    final version = ++_searchVersion;
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) {
      context.read<ContactProvider>().clearDirectoryResults();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () async {
      await context.read<ContactProvider>().searchDirectoryByPhone(
            query: value,
            countryIso: _countryIso,
          );
      if (!mounted || version != _searchVersion) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactProvider>();
    final query = _search.text.trim();
    final queryDigits = query.replaceAll(RegExp(r'[^0-9]'), '');

    final local = contacts.deviceMatches
        .where((item) => !widget.excludedProfileIds.contains(item.profileId))
        .where((item) => _matchesDeviceContact(item, query))
        .toList();
    final localIds = local.map((item) => item.profileId).toSet();
    final directory = queryDigits.length < 6
        ? const <ContactMatch>[]
        : contacts.directoryResults
            .where(
              (item) =>
                  !widget.excludedProfileIds.contains(item.user.id) &&
                  !localIds.contains(item.user.id),
            )
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_addingToGroup ? 'Add participants' : 'New chat'),
        actions: [
          IconButton(
            tooltip: 'Refresh phone contacts',
            onPressed: contacts.loading
                ? null
                : () => contacts.sync(force: true),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: CountryPhoneField(
              controller: _search,
              initialCountryIso: _countryIso,
              labelText: 'Search mobile number',
              textInputAction: TextInputAction.search,
              onCountryChanged: (value) {
                _countryIso = value;
                if (_search.text.trim().isNotEmpty) {
                  _onSearchChanged(_search.text);
                }
              },
              onFieldSubmitted: _onSearchChanged,
              onChanged: _onSearchChanged,
              validate: false,
              autofocus: true,
            ),
          ),
          if (contacts.permissionDenied)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Text(
                'Contacts permission is off. You can still search registered Taskly users below.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.taskly.warning),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => contacts.sync(force: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 30),
                children: [
                  _SectionHeader(
                    title: 'Contacts on Taskly',
                    subtitle: 'Registered people found in your phone contacts',
                    loading: contacts.loading,
                  ),
                  if (contacts.loading && local.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (local.isEmpty)
                    const _EmptySection(
                      text: 'No matching registered phone contacts found.',
                    )
                  else
                    ...local.map(
                      (item) => _PersonTile(
                        name: item.deviceName,
                        subtitle: _localSubtitle(item),
                        initials: item.match.user.initials,
                        busy: _busyProfileId == item.profileId,
                        onTap: () => _select(item.match),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _SectionHeader(
                    title: 'Taskly directory',
                    subtitle: queryDigits.length < 6
                        ? 'Enter at least 6 digits to search registered users'
                        : 'Results from registered Taskly accounts',
                    loading: contacts.loadingDirectory,
                  ),
                  if (queryDigits.length < 6)
                    const _EmptySection(
                      text: 'Database results appear only after you search a mobile number.',
                    )
                  else if (contacts.loadingDirectory)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (contacts.directoryError != null)
                    _EmptySection(text: contacts.directoryError!)
                  else if (directory.isEmpty)
                    const _EmptySection(
                      text: 'No registered Taskly user matches this number.',
                    )
                  else
                    ...directory.map(
                      (match) => _PersonTile(
                        name: match.user.name,
                        subtitle: match.user.phone ?? match.user.email,
                        initials: match.user.initials,
                        busy: _busyProfileId == match.user.id,
                        onTap: () => _select(match),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesDeviceContact(DeviceTasklyContact item, String query) {
    if (query.isEmpty) return true;
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    final itemDigits = [
      item.devicePhone,
      item.match.user.phone ?? '',
    ].join().replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty || itemDigits.contains(digits);
  }

  String _localSubtitle(DeviceTasklyContact item) {
    final phone = item.match.user.phone ?? item.devicePhone;
    if (item.deviceName.toLowerCase() == item.match.user.name.toLowerCase()) {
      return phone;
    }
    return '${item.match.user.name} · $phone';
  }

  Future<void> _select(ContactMatch match) async {
    if (_busyProfileId != null) return;
    setState(() => _busyProfileId = match.user.id);
    try {
      if (_addingToGroup) {
        final workspaceId = widget.workspaceId;
        final channelId = widget.channelId;
        if (workspaceId == null || channelId == null) {
          throw StateError('Group information is missing');
        }
        await context.read<ChatProvider>().addGroupMemberByProfileId(
              workspaceId: workspaceId,
              channelId: channelId,
              profileId: match.user.id,
            );
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      final conversation =
          await context.read<ChatProvider>().startDirectChat(match.user);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(conversation: conversation),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.loading,
  });

  final String title;
  final String subtitle;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.taskly.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.name,
    required this.subtitle,
    required this.initials,
    required this.busy,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final String initials;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        leading: CircleAvatar(child: Text(initials)),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right),
        onTap: busy ? null : onTap,
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.taskly.textMuted),
        ),
      ),
    );
  }
}
