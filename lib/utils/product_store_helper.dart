import '../models/models.dart';
import 'json_parsers.dart';

/// Normalizes store identifiers on a product map for detail/navigation screens.
Map<String, dynamic> productToDetailMap(dynamic product) {
  final map = product is Product
      ? product.toJson()
      : Map<String, dynamic>.from(product as Map);

  final storeId = map['store_id'] ?? map['shop_id'];
  if (storeId != null) {
    map['store_id'] = storeId;
    map['shop_id'] = storeId;
  }

  return map;
}

Store? storeFromProductMap(Map<String, dynamic> product) {
  final id = product['shop_id'] ?? product['store_id'];
  final name = product['shop_name']?.toString();
  if (id == null && (name == null || name.isEmpty)) return null;

  return Store(
    id: id,
    name: name ?? '',
    city: product['city']?.toString() ?? product['store_city']?.toString(),
    country:
        product['country']?.toString() ?? product['store_country']?.toString(),
    lat: parseJsonDouble(product['lat']),
    lng: parseJsonDouble(product['lng']),
    imageUrl: product['store_image_url']?.toString(),
  );
}
