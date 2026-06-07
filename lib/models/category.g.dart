// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Category _$CategoryFromJson(Map<String, dynamic> json) => Category(
  id: (json['id'] as num?)?.toInt(),
  name: json['name'] as String,
  icon: json['icon'] as String?,
  translations: json['translations'] as Map<String, dynamic>?,
  sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  parentId: (json['parent_id'] as num?)?.toInt(),
);

Map<String, dynamic> _$CategoryToJson(Category instance) => <String, dynamic>{
  'id': ?instance.id,
  'name': instance.name,
  'icon': ?instance.icon,
  'translations': ?instance.translations,
  'sort_order': instance.sortOrder,
  'parent_id': ?instance.parentId,
};
