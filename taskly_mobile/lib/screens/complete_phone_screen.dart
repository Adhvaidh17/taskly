import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../core/utils/phone_number.dart';
import '../providers/auth_provider.dart';
import '../widgets/country_phone_field.dart';

class CompletePhoneScreen extends StatefulWidget {
  const CompletePhoneScreen({super.key});

  @override
  State<CompletePhoneScreen> createState() => _CompletePhoneScreenState();
}

class _CompletePhoneScreenState extends State<CompletePhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late String _countryIso;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _countryIso = user?.phoneCountryIso ??
        TasklyPhoneNumber.countryIso(user?.phone) ??
        AppConfig.defaultCountryIso;
    _name = TextEditingController(text: user?.name ?? '');
    _phone = TextEditingController(
      text: TasklyPhoneNumber.nationalNumber(user?.phone),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.completeMandatoryProfile(
      name: _name.text,
      phone: _phone.text,
      countryIso: _countryIso,
      about: auth.user?.about,
    );
    if (!mounted || success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(auth.error ?? 'Unable to save your mobile number')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.phone_android, size: 58),
                    const SizedBox(height: 18),
                    const Text(
                      'Add your mobile number',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Choose your country. A mobile number is mandatory for Taskly contacts and account identification.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.taskly.textMuted),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) => (value ?? '').trim().length < 2
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    CountryPhoneField(
                      controller: _phone,
                      initialCountryIso: _countryIso,
                      onCountryChanged: (value) => _countryIso = value,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: auth.busy ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: auth.busy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save and continue'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: auth.busy ? null : auth.logout,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
