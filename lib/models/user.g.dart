// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
  id: (json['id'] as num?)?.toInt(),
  fullName: json['full_name'] as String?,
  email: json['email'] as String?,
  phone: json['phone'] as String?,
  avatarUrl: json['avatar_url'] as String?,
  role: json['role'] as String?,
  store: json['store'] as Map<String, dynamic>?,
  preferredLanguage: json['preferred_language'] as String?,
  isVerified: json['is_verified'] as bool?,
  createdAt: json['created_at'] as String?,
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': ?instance.id,
  'full_name': ?instance.fullName,
  'email': ?instance.email,
  'phone': ?instance.phone,
  'avatar_url': ?instance.avatarUrl,
  'role': ?instance.role,
  'store': ?instance.store,
  'preferred_language': ?instance.preferredLanguage,
  'is_verified': ?instance.isVerified,
  'created_at': ?instance.createdAt,
};
