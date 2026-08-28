import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../config/app_config.dart';

class TasklyPhoneNumber {
  const TasklyPhoneNumber._();

  static IsoCode _isoCode(String? countryIso) {
    final code = (countryIso ?? AppConfig.defaultCountryIso).trim().toUpperCase();
    try {
      return IsoCode.values.byName(code);
    } catch (_) {
      return IsoCode.IN;
    }
  }

  static String normalize(
    String value, {
    String? countryIso,
  }) {
    final input = value.trim();
    if (input.isEmpty) return '';

    try {
      final hasInternationalPrefix = input.startsWith('+') || input.startsWith('00');
      final number = PhoneNumber.parse(
        input,
        callerCountry: hasInternationalPrefix ? null : _isoCode(countryIso),
      );
      return number.international;
    } catch (_) {
      var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.startsWith('00')) digits = digits.substring(2);
      if (digits.isEmpty) return '';

      if (!input.startsWith('+') && !input.startsWith('00')) {
        try {
          final country = PhoneNumber(
            isoCode: _isoCode(countryIso),
            nsn: digits.replaceFirst(RegExp(r'^0+'), ''),
          );
          return country.international;
        } catch (_) {
          return '';
        }
      }
      return '+$digits';
    }
  }

  static bool isValid(
    String value, {
    String? countryIso,
  }) {
    try {
      final normalized = normalize(value, countryIso: countryIso);
      if (normalized.isEmpty) return false;
      return PhoneNumber.parse(normalized).isValid();
    } catch (_) {
      return false;
    }
  }

  static String? countryIso(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return null;
    try {
      return PhoneNumber.parse(input).isoCode.name;
    } catch (_) {
      return null;
    }
  }

  static String nationalNumber(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return '';
    try {
      return PhoneNumber.parse(input).nsn;
    } catch (_) {
      return input.replaceAll(RegExp(r'[^0-9]'), '');
    }
  }
}
