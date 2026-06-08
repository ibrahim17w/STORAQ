import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lang/translations.dart';
import '../utils/phone_helper.dart';

class PhoneTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final IconData prefixIcon;
  final bool required;

  const PhoneTextField({
    super.key,
    required this.controller,
    this.labelText,
    this.validator,
    this.textInputAction,
    this.prefixIcon = Icons.phone_outlined,
    this.required = true,
  });

  String? _defaultValidator(String? value) {
    if (required && (value == null || value.trim().isEmpty)) {
      return t('enter_phone') ?? 'Enter your phone number';
    }
    if (value != null && value.trim().isNotEmpty) {
      final err = PhoneHelper.validateDigits(value);
      if (err != null) {
        return t('invalid_credentials') ?? 'Invalid phone';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        textInputAction: textInputAction,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          labelText: labelText ?? t('phone') ?? 'Phone',
          prefixIcon: Icon(prefixIcon),
          prefixText: '+',
          border: const OutlineInputBorder(),
        ),
        validator: validator ?? _defaultValidator,
      ),
    );
  }
}
