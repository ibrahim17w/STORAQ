import 'legal_policies_ar.dart';
import 'legal_policies_bn.dart';
import 'legal_policies_en.dart';
import 'legal_policies_es.dart';
import 'legal_policies_fr.dart';
import 'legal_policies_hi.dart';
import 'legal_policies_ru.dart';
import 'legal_policies_tr.dart';
import 'legal_policies_ur.dart';
import 'legal_policies_zh.dart';

/// Legal policy translation keys for all supported locales.
const Map<String, Map<String, String>> legalPolicies = {
  'en': legalPoliciesEn,
  'ar': legalPoliciesAr,
  'fr': legalPoliciesFr,
  'es': legalPoliciesEs,
  'tr': legalPoliciesTr,
  'ur': legalPoliciesUr,
  'hi': legalPoliciesHi,
  'bn': legalPoliciesBn,
  'ru': legalPoliciesRu,
  'zh': legalPoliciesZh,
};

/// Policy document keys shown in the legal documents hub.
const List<String> legalPolicyDocKeys = [
  'terms_of_service',
  'privacy_policy',
  'refund_policy',
  'content_policy',
  'seller_rules',
];
