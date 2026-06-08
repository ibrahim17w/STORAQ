// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'store.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Store _$StoreFromJson(Map<String, dynamic> json) => Store(
  id: json['id'],
  name: json['name'] as String?,
  city: json['city'] as String?,
  cityId: json['city_id'] as String?,
  cityDisplayNames: json['city_display_names'] as Map<String, dynamic>?,
  village: json['village'] as String?,
  villageId: json['village_id'] as String?,
  country: json['country'] as String?,
  countryCode: json['country_code'] as String?,
  lat: parseJsonDouble(json['lat']),
  lng: parseJsonDouble(json['lng']),
  phone: json['phone'] as String?,
  imageUrl: json['image_url'] as String?,
  isActive: json['is_active'] as bool?,
  role: json['role'] as String?,
  ownerId: parseJsonInt(json['owner_id']),
  displayCurrency: json['display_currency'] as String?,
  showBothPrices: json['show_both_prices'] as bool?,
  exchangeRates: json['exchange_rates'],
  manualApprovalMode: json['manual_approval_mode'] as bool?,
  firstProductApproved: json['first_product_approved'] as bool?,
  createdAt: json['created_at'] as String?,
  rating: parseJsonDouble(json['rating']),
  reviewCount: parseJsonInt(json['review_count']),
);

Map<String, dynamic> _$StoreToJson(Store instance) => <String, dynamic>{
  'id': ?instance.id,
  'name': ?instance.name,
  'city': ?instance.city,
  'city_id': ?instance.cityId,
  'city_display_names': ?instance.cityDisplayNames,
  'village': ?instance.village,
  'village_id': ?instance.villageId,
  'country': ?instance.country,
  'country_code': ?instance.countryCode,
  'lat': ?instance.lat,
  'lng': ?instance.lng,
  'phone': ?instance.phone,
  'image_url': ?instance.imageUrl,
  'is_active': ?instance.isActive,
  'role': ?instance.role,
  'owner_id': ?instance.ownerId,
  'display_currency': ?instance.displayCurrency,
  'show_both_prices': ?instance.showBothPrices,
  'exchange_rates': ?instance.exchangeRates,
  'manual_approval_mode': ?instance.manualApprovalMode,
  'first_product_approved': ?instance.firstProductApproved,
  'created_at': ?instance.createdAt,
  'rating': ?instance.rating,
  'review_count': ?instance.reviewCount,
};
