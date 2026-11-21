/// Central configuration for outbound cash-pharmacy referral links,
/// optional tip jar support, and official legal URLs.
///
/// Privacy guarantee: Every link contains ONLY the public medication name.
/// Zero personal identifiers, account tokens, or cabinet lists are ever included.
class PartnerLinks {
  // Optional affiliate/referral IDs — fill in whenever you receive partner tags
  static const String amazonAssociatesTag = ''; // e.g., 'danglingdice-20'
  static const String singleCarePartnerParam = ''; // e.g., 'utm_source=danglingdice'
  static const String goodRxPartnerParam = ''; // e.g., 'utm_source=danglingdice'

  // Optional non-nagging tip jar URL (e.g., Stripe Payment Link, Ko-fi, or Buy Me a Coffee)
  static const String tipJarUrl = 'https://dangling-dice-studios.com/';

  // Official legal URLs
  static const String privacyPolicyUrl = 'https://dangling-dice-studios.com/rx-savings-watch/privacy.html';
  static const String termsOfServiceUrl = 'https://dangling-dice-studios.com/rx-savings-watch/terms.html';

  static String _cleanDrugSlug(String name) {
    final first = name.trim().toLowerCase().split(RegExp(r'\s+')).first;
    return first.replaceAll(RegExp(r'[^a-z0-9\-]'), '');
  }

  static Uri buildCostPlusDrugsUrl(String genericName) {
    final q = Uri.encodeQueryComponent(genericName.trim().split(' ').first);
    return Uri.parse('https://www.costplusdrugs.com/medications/?search=$q');
  }

  static Uri buildAmazonPharmacyUrl(String drugName) {
    final q = Uri.encodeQueryComponent(drugName.trim());
    final tagSuffix = amazonAssociatesTag.isNotEmpty
        ? '&tag=${Uri.encodeQueryComponent(amazonAssociatesTag)}'
        : '';
    return Uri.parse('https://pharmacy.amazon.com/s?k=$q$tagSuffix');
  }

  static Uri buildSingleCareUrl(String drugName) {
    final slug = _cleanDrugSlug(drugName);
    final suffix = singleCarePartnerParam.isNotEmpty ? '?$singleCarePartnerParam' : '';
    return Uri.parse('https://www.singlecare.com/prescription/$slug$suffix');
  }

  static Uri buildGoodRxUrl(String drugName) {
    final slug = _cleanDrugSlug(drugName);
    final suffix = goodRxPartnerParam.isNotEmpty ? '?$goodRxPartnerParam' : '';
    return Uri.parse('https://www.goodrx.com/$slug$suffix');
  }
}
