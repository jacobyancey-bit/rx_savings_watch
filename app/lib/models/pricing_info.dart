class PricingInfo {
  final double? brandNadacUnitPrice;
  final double? genericNadacUnitPrice;
  final double? estimatedSavingsPct;

  PricingInfo({
    this.brandNadacUnitPrice,
    this.genericNadacUnitPrice,
    this.estimatedSavingsPct,
  });

  factory PricingInfo.fromJson(Map<String, dynamic> json) {
    return PricingInfo(
      brandNadacUnitPrice: (json['brand_nadac_unit_price'] as num?)?.toDouble(),
      genericNadacUnitPrice: (json['generic_nadac_unit_price'] as num?)?.toDouble(),
      estimatedSavingsPct: (json['estimated_savings_pct'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'brand_nadac_unit_price': brandNadacUnitPrice,
      'generic_nadac_unit_price': genericNadacUnitPrice,
      'estimated_savings_pct': estimatedSavingsPct,
    };
  }
}
