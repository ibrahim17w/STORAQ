import 'package:json_annotation/json_annotation.dart';

part 'category.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class Category {
  final int? id;
  final String name;
  final String? icon;
  final Map<String, dynamic>? translations;
  @JsonKey(name: 'sort_order')
  final int sortOrder;
  @JsonKey(name: 'parent_id')
  final int? parentId;

  const Category({
    this.id,
    required this.name,
    this.icon,
    this.translations,
    this.sortOrder = 0,
    this.parentId,
  });

  factory Category.fromJson(Map<String, dynamic> json) =>
      _$CategoryFromJson(json);

  Map<String, dynamic> toJson() => _$CategoryToJson(this);

  String localizedName(String languageCode) {
    if (translations == null) return name;
    return translations![languageCode]?.toString() ?? name;
  }
}
