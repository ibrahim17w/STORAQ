class PhoneHelper {
  PhoneHelper._();

  /// Strip leading "+" from stored phone values for editing.
  static String digitsFromStored(String? phone) {
    if (phone == null) return '';
    return phone.trim().replaceFirst(RegExp(r'^\+'), '');
  }

  /// Format user-entered digits as an international phone number.
  static String toStored(String digits) {
    final trimmed = digits.trim();
    if (trimmed.isEmpty) return '';
    return '+$trimmed';
  }

  static String? validateDigits(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // caller supplies required message via wrapper if needed
    }
    if (value.trim().length < 7) {
      return 'invalid';
    }
    return null;
  }
}
