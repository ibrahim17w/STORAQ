import 'package:json_annotation/json_annotation.dart';
import '../utils/json_parsers.dart';

part 'store.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class Store {
  final dynamic id;
  final String? name;
  final String? city;
  @JsonKey(name: 'city_id')
  final String? cityId;
  final String? village;
  @JsonKey(name: 'village_id')
  final String? villageId;
  final String? country;
  @JsonKey(name: 'country_code')
  final String? countryCode;
  @JsonKey(fromJson: parseJsonDouble)
  final double? lat;
  @JsonKey(fromJson: parseJsonDouble)
  final double? lng;
  final String? phone;
  @JsonKey(name: 'image_url')
  final String? imageUrl;
  @JsonKey(name: 'is_active')
  final bool? isActive;
  final String? role;
  @JsonKey(name: 'owner_id', fromJson: parseJsonInt)
  final int? ownerId;
  @JsonKey(name: 'display_currency')
  final String? displayCurrency;
  @JsonKey(name: 'show_both_prices')
  final bool? showBothPrices;
  @JsonKey(name: 'exchange_rates')
  final dynamic exchangeRates;
  @JsonKey(name: 'manual_approval_mode')
  final bool? manualApprovalMode;
  @JsonKey(name: 'first_product_approved')
  final bool? firstProductApproved;
  @JsonKey(name: 'created_at')
  final String? createdAt;

  const Store({
    this.id,
    this.name,
    this.city,
    this.cityId,
    this.village,
    this.villageId,
    this.country,
    this.countryCode,
    this.lat,
    this.lng,
    this.phone,
    this.imageUrl,
    this.isActive,
    this.role,
    this.ownerId,
    this.displayCurrency,
    this.showBothPrices,
    this.exchangeRates,
    this.manualApprovalMode,
    this.firstProductApproved,
    this.createdAt,
  });

  factory Store.fromJson(Map<String, dynamic> json) => _$StoreFromJson(json);

  Map<String, dynamic> toJson() => _$StoreToJson(this);

  int? get intId {
    if (id == null) return null;
    if (id is int) return id as int;
    return int.tryParse(id.toString());
  }

  Store copyWith({
    dynamic id,
    String? name,
    String? city,
    String? village,
    String? country,
    double? lat,
    double? lng,
    String? phone,
    String? imageUrl,
    bool? isActive,
    String? role,
  }) {
    return Store(
      id: id ?? this.id,
      name: name ?? this.name,
      city: city ?? this.city,
      cityId: cityId,
      village: village ?? this.village,
      villageId: villageId,
      country: country ?? this.country,
      countryCode: countryCode,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      phone: phone ?? this.phone,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      role: role ?? this.role,
      ownerId: ownerId,
      displayCurrency: displayCurrency,
      showBothPrices: showBothPrices,
      exchangeRates: exchangeRates,
      manualApprovalMode: manualApprovalMode,
      firstProductApproved: firstProductApproved,
      createdAt: createdAt,
    );
  }
}
