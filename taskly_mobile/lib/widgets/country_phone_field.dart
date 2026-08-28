import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/utils/phone_number.dart';

class CountryPhoneField extends StatefulWidget {
  const CountryPhoneField({
    super.key,
    required this.controller,
    required this.onCountryChanged,
    this.initialCountryIso,
    this.labelText = 'Mobile number',
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.onChanged,
    this.validate = true,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onCountryChanged;
  final String? initialCountryIso;
  final String labelText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final bool validate;
  final bool autofocus;

  @override
  State<CountryPhoneField> createState() => _CountryPhoneFieldState();
}

class _CountryPhoneFieldState extends State<CountryPhoneField> {
  late Country _country;

  @override
  void initState() {
    super.initState();
    _country = _countryFor(widget.initialCountryIso);
  }

  @override
  void didUpdateWidget(covariant CountryPhoneField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requested = (widget.initialCountryIso ?? '').toUpperCase();
    if (requested.isNotEmpty && requested != _country.countryCode) {
      _country = _countryFor(requested);
    }
  }

  Country _countryFor(String? iso) {
    final requested = (iso ?? AppConfig.defaultCountryIso).toUpperCase();
    return CountryService().findByCode(requested) ??
        CountryService().findByCode('IN')!;
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      favorite: const ['IN', 'US', 'GB', 'AE', 'SG', 'AU', 'CA'],
      countryListTheme: CountryListThemeData(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        textStyle: Theme.of(context).textTheme.bodyLarge,
        searchTextStyle: Theme.of(context).textTheme.bodyLarge,
        inputDecoration: const InputDecoration(
          labelText: 'Search country or code',
          prefixIcon: Icon(Icons.search),
        ),
        bottomSheetHeight: MediaQuery.sizeOf(context).height * 0.78,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      onSelect: (country) {
        setState(() => _country = country);
        widget.onCountryChanged(country.countryCode);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.phone,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: _country.example,
        prefixIconConstraints: const BoxConstraints(minWidth: 108),
        prefixIcon: InkWell(
          onTap: _pickCountry,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_country.flagEmoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 7),
                Text(
                  '+${_country.phoneCode}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
      ),
      validator: widget.validate
          ? (value) => TasklyPhoneNumber.isValid(
                value ?? '',
                countryIso: _country.countryCode,
              )
                  ? null
                  : 'Enter a valid mobile number'
          : null,
    );
  }
}
