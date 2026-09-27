import 'package:dlibphonenumber/dlibphonenumber.dart';

class PhoneNumberService {
  PhoneNumberService({PhoneNumberUtil? phoneNumberUtil})
    : _phoneNumberUtil = phoneNumberUtil ?? PhoneNumberUtil.instance;

  final PhoneNumberUtil _phoneNumberUtil;

  String? validate(String? value, String regionCode) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }

    try {
      final parsedNumber = _phoneNumberUtil.parse(value.trim(), regionCode);
      if (!_phoneNumberUtil.isValidNumber(parsedNumber)) {
        return 'Please enter a valid phone number for the selected country';
      }
      return null;
    } catch (_) {
      return 'Invalid phone number format';
    }
  }

  String formatToE164(String value, String regionCode) {
    final validationError = validate(value, regionCode);
    if (validationError != null) {
      throw FormatException(validationError);
    }
    final parsedNumber = _phoneNumberUtil.parse(value.trim(), regionCode);
    return _phoneNumberUtil.format(parsedNumber, PhoneNumberFormat.e164);
  }
}