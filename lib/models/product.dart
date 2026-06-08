import 'package:json_annotation/json_annotation.dart';
import '../utils/json_parsers.dart';

part 'product.g.dart';

Object? readStoreId(Map json, String key) => json['store_id'] ?? json['shop_id'];

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class Product {
  final dynamic id;
  final String? name;
  @JsonKey(fromJson: parseJsonDouble)
  final double? price;
  @JsonKey(name: 'sale_price', fromJson: parseJsonDouble)
  final double? salePrice;
  @JsonKey(name: 'is_on_sale')
  final bool? isOnSale;
  @JsonKey(fromJson: parseJsonInt)
  final int? quantity;
  final String? description;
  final String? barcode;
  @JsonKey(name: 'category_id', fromJson: parseJsonInt)
  final int? categoryId;
  final String? currency;
  @JsonKey(name: 'image_url')
  final String? imageUrl;
  final List<String>? images;
  @JsonKey(name: 'local_images')
  final List<String>? localImages;
  @JsonKey(name: 'is_online')
  final bool? isOnline;
  @JsonKey(name: 'went_online_at')
  final String? wentOnlineAt;
  @JsonKey(name: 'view_count', fromJson: parseJsonInt)
  final int? viewCount;
  @JsonKey(fromJson: parseJsonDouble)
  final double? rating;
  @JsonKey(name: 'review_count', fromJson: parseJsonInt)
  final int? reviewCount;
  @JsonKey(name: 'shop_name')
  final String? shopName;
  @JsonKey(name: 'store_id', readValue: readStoreId, fromJson: parseJsonInt)
  final int? storeId;
  @JsonKey(fromJson: parseJsonDouble)
  final double? lat;
  @JsonKey(fromJson: parseJsonDouble)
  final double? lng;
  final String? city;
  @JsonKey(name: 'city_id')
  final String? cityId;
  final String? village;
  @JsonKey(name: 'village_id')
  final String? villageId;
  final String? country;
  @JsonKey(name: 'country_code')
  final String? countryCode;
  @JsonKey(name: 'store_city')
  final String? storeCity;
  @JsonKey(name: 'store_village')
  final String? storeVillage;
  @JsonKey(name: 'store_country')
  final String? storeCountry;
  @JsonKey(name: 'display_price', fromJson: parseJsonDouble)
  final double? displayPrice;
  @JsonKey(name: 'display_currency')
  final String? displayCurrency;
  @JsonKey(name: 'low_stock_threshold', fromJson: parseJsonInt)
  final int? lowStockThreshold;
  @JsonKey(name: 'created_at')
  final String? createdAt;
  @JsonKey(name: 'updated_at')
  final String? updatedAt;
  @JsonKey(name: 'image_path')
  final String? imagePath;
  @JsonKey(name: '_pendingCreate')
  final bool? pendingCreate;
  @JsonKey(name: '_pendingUpdate')
  final bool? pendingUpdate;
  @JsonKey(name: 'pending_approval')
  final bool? pendingApproval;
  @JsonKey(name: 'list_online')
  final bool? listOnline;

  const Product({
    this.id,
    this.name,
    this.price,
    this.salePrice,
    this.isOnSale,
    this.quantity,
    this.description,
    this.barcode,
    this.categoryId,
    this.currency,
    this.imageUrl,
    this.images,
    this.localImages,
    this.isOnline,
    this.wentOnlineAt,
    this.viewCount,
    this.rating,
    this.reviewCount,
    this.shopName,
    this.storeId,
    this.lat,
    this.lng,
    this.city,
    this.cityId,
    this.village,
    this.villageId,
    this.country,
    this.countryCode,
    this.storeCity,
    this.storeVillage,
    this.storeCountry,
    this.displayPrice,
    this.displayCurrency,
    this.lowStockThreshold,
    this.createdAt,
    this.updatedAt,
    this.imagePath,
    this.pendingCreate,
    this.pendingUpdate,
    this.pendingApproval,
    this.listOnline,
  });

  factory Product.fromJson(Map<String, dynamic> json) =>
      _$ProductFromJson(json);

  Map<String, dynamic> toJson() => _$ProductToJson(this);

  int? get intId {
    if (id == null) return null;
    if (id is int) return id as int;
    return int.tryParse(id.toString());
  }

  Product copyWith({
    dynamic id,
    String? name,
    double? price,
    double? salePrice,
    bool? isOnSale,
    int? quantity,
    String? description,
    String? barcode,
    int? categoryId,
    String? currency,
    String? imageUrl,
    List<String>? images,
    List<String>? localImages,
    bool? isOnline,
    int? viewCount,
    double? rating,
    String? shopName,
    int? storeId,
    double? displayPrice,
    String? displayCurrency,
    bool? pendingCreate,
    bool? pendingUpdate,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      salePrice: salePrice ?? this.salePrice,
      isOnSale: isOnSale ?? this.isOnSale,
      quantity: quantity ?? this.quantity,
      description: description ?? this.description,
      barcode: barcode ?? this.barcode,
      categoryId: categoryId ?? this.categoryId,
      currency: currency ?? this.currency,
      imageUrl: imageUrl ?? this.imageUrl,
      images: images ?? this.images,
      localImages: localImages ?? this.localImages,
      isOnline: isOnline ?? this.isOnline,
      wentOnlineAt: wentOnlineAt,
      viewCount: viewCount ?? this.viewCount,
      rating: rating ?? this.rating,
      shopName: shopName ?? this.shopName,
      storeId: storeId ?? this.storeId,
      lat: lat,
      lng: lng,
      city: city,
      cityId: cityId,
      village: village,
      villageId: villageId,
      country: country,
      countryCode: countryCode,
      storeCity: storeCity,
      storeVillage: storeVillage,
      storeCountry: storeCountry,
      displayPrice: displayPrice ?? this.displayPrice,
      displayCurrency: displayCurrency ?? this.displayCurrency,
      lowStockThreshold: lowStockThreshold,
      createdAt: createdAt,
      updatedAt: updatedAt,
      imagePath: imagePath,
      pendingCreate: pendingCreate ?? this.pendingCreate,
      pendingUpdate: pendingUpdate ?? this.pendingUpdate,
      pendingApproval: pendingApproval,
      listOnline: listOnline,
    );
  }
}
