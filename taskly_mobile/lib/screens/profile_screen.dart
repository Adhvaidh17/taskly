import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../core/notifications/push_notification_service.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/phone_number.dart';
import '../models/channel.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/workspace_provider.dart';
import '../widgets/country_phone_field.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkspaceProvider>();
    final auth = context.watch<AuthProvider>();
    final profile = provider.profile;
    if (provider.loading && profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: provider.load,
      child: ListView(
        key: const PageStorageKey('profile'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(radius: 34, child: Text(profile?.initials ?? '?', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile?.name ?? 'Taskly user', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(
                          profile?.phone ?? 'Mobile number required',
                          style: TextStyle(color: context.taskly.textMuted),
                        ),
                        Text(
                          profile?.email ?? '',
                          style: TextStyle(
                            color: context.taskly.textFaint,
                            fontSize: 12,
                          ),
                        ),
                        if ((profile?.phone ?? '').isNotEmpty)
                          Text(
                            auth.verifiedAuthPhone == profile?.phone
                                ? 'Mobile verified for login'
                                : 'Verify mobile to use it for login',
                            style: TextStyle(
                              color: auth.verifiedAuthPhone == profile?.phone
                                  ? context.taskly.success
                                  : context.taskly.warning,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        ),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                      IconButton(
                        tooltip: 'Edit profile',
                        onPressed: profile == null ? null : () => _editProfile(context),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if ((profile?.phone ?? '').isNotEmpty &&
              auth.verifiedAuthPhone != profile?.phone) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: auth.busy
                  ? null
                  : () => _verifyMobileForLogin(context, profile!.phone!),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Verify mobile for login'),
            ),
          ],
          const SizedBox(height: 14),
          const SizedBox(height: 8),
          const SizedBox(height: 18),
          const Text('People', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.contacts_outlined),
              title: const Text('People on Taskly'),
              subtitle: const Text('Match your contacts by phone first, then email'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactsScreen())),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () async {
              await context.read<PushNotificationService>().unbind();
              if (context.mounted) await context.read<AuthProvider>().logout();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    final provider = context.read<WorkspaceProvider>();
    final profile = provider.profile!;
    final name = TextEditingController(text: profile.name);
    var countryIso = profile.phoneCountryIso ??
        TasklyPhoneNumber.countryIso(profile.phone) ??
        AppConfig.defaultCountryIso;
    final phone = TextEditingController(
      text: TasklyPhoneNumber.nationalNumber(profile.phone),
    );
    final about = TextEditingController(text: profile.about);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              CountryPhoneField(
                controller: phone,
                initialCountryIso: countryIso,
                onCountryChanged: (value) => countryIso = value,
                labelText: 'Mobile number',
              ),
              const SizedBox(height: 10),
              TextField(controller: about, maxLength: 120, decoration: const InputDecoration(labelText: 'About')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || !context.mounted) return;
    final normalizedPhone = TasklyPhoneNumber.normalize(
      phone.text,
      countryIso: countryIso,
    );
    if (!TasklyPhoneNumber.isValid(normalizedPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A valid mobile number is required')),
      );
      return;
    }
    try {
      await provider.updateMyProfile(
        name: name.text,
        phone: normalizedPhone,
        phoneCountryIso: countryIso,
        about: about.text,
      );
      if (!context.mounted) return;
      await context.read<AuthProvider>().refreshProfile();
      if (!context.mounted) return;
      final auth = context.read<AuthProvider>();
      if (auth.verifiedAuthPhone != normalizedPhone) {
        final verify = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Verify mobile for login?'),
            content: Text(
              'Taskly saved $normalizedPhone. Verify it by SMS to sign in using this mobile number.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Verify'),
              ),
            ],
          ),
        );
        if (verify == true && context.mounted) {
          await _verifyMobileForLogin(context, normalizedPhone);
        }
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  Future<void> _verifyMobileForLogin(
    BuildContext context,
    String phone,
  ) async {
    final auth = context.read<AuthProvider>();
    final normalizedPhone = TasklyPhoneNumber.normalize(phone);
    if (auth.verifiedAuthPhone == normalizedPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mobile number is already verified')),
      );
      return;
    }

    final requested = await auth.requestPhoneVerification(normalizedPhone);
    if (!context.mounted) return;
    if (!requested) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            auth.error ??
                'Could not send OTP. Configure the Supabase Phone Auth provider first.',
          ),
        ),
      );
      return;
    }

    final otp = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter verification code'),
        content: TextField(
          controller: otp,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: '6-digit OTP',
            helperText: 'Sent to $normalizedPhone',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    if (submit != true || !context.mounted) return;

    final verified = await auth.verifyPhoneChange(
      phone: normalizedPhone,
      otp: otp.text,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          verified
              ? 'Mobile number verified. You can now use it to sign in.'
              : auth.error ?? 'OTP verification failed',
        ),
      ),
    );
  }

}
