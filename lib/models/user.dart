import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: false)
class User {
  final int? id;
  @JsonKey(name: 'full_name')
  final String? fullName;
  final String? email;
  final String? phone;
  @JsonKey(name: 'avatar_url')
  final String? avatarUrl;
  final String? role;
  final Map<String, dynamic>? store;
  @JsonKey(name: 'preferred_language')
  final String? preferredLanguage;
  @JsonKey(name: 'is_verified')
  final bool? isVerified;
  @JsonKey(name: 'created_at')
  final String? createdAt;

  const User({
    this.id,
    this.fullName,
    this.email,
    this.phone,
    this.avatarUrl,
    this.role,
    this.store,
    this.preferredLanguage,
    this.isVerified,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  Map<String, dynamic> toJson() => _$UserToJson(this);

  User copyWith({
    int? id,
    String? fullName,
    String? email,
    String? phone,
    String? avatarUrl,
    String? role,
    Map<String, dynamic>? store,
    String? preferredLanguage,
  }) {
    return User(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      store: store ?? this.store,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      isVerified: isVerified,
      createdAt: createdAt,
    );
  }
}
