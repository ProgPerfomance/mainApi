import 'package:mongo_dart/mongo_dart.dart';

class SubscriptionPlan {
  const SubscriptionPlan({
    this.id,
    required this.name,
    required this.scope,
    required this.appIds,
    required this.benefitType,
    this.discountPercent,
    required this.price,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final ObjectId? id;
  final String name;
  final String scope;
  final List<String> appIds;
  final String benefitType;
  final double? discountPercent;
  final double price;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get primaryAppId => appIds.isEmpty ? 'global' : appIds.first;

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: _parseObjectId(json['_id']),
      name: json['name']?.toString() ?? '',
      scope: _normalizeScope(json['scope']?.toString()),
      appIds: _parseAppIds(json['appIds'] ?? json['app_ids']),
      benefitType: _normalizeBenefitType(
        json['benefitType']?.toString() ?? json['benefit_type']?.toString(),
      ),
      discountPercent:
          (json['discountPercent'] as num?)?.toDouble() ??
          (json['discount_percent'] as num?)?.toDouble(),
      price: (json['price'] as num?)?.toDouble() ?? 0,
      isActive: json['isActive'] != false,
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now().toUtc(),
      updatedAt: _parseDateTime(json['updatedAt']) ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id,
      'name': name,
      'scope': scope,
      'appIds': appIds,
      'app_ids': appIds,
      'benefitType': benefitType,
      'benefit_type': benefitType,
      if (discountPercent != null) 'discountPercent': discountPercent,
      'price': price,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toPublicJson() {
    return {
      '_id': id?.oid,
      'name': name,
      'scope': scope,
      'appIds': appIds,
      'app_ids': appIds,
      'benefitType': benefitType,
      'benefit_type': benefitType,
      if (discountPercent != null) 'discountPercent': discountPercent,
      'price': price,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  SubscriptionPlan copyWith({
    String? name,
    String? scope,
    List<String>? appIds,
    String? benefitType,
    double? discountPercent,
    bool clearDiscountPercent = false,
    double? price,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return SubscriptionPlan(
      id: id,
      name: name ?? this.name,
      scope: scope ?? this.scope,
      appIds: appIds ?? this.appIds,
      benefitType: benefitType ?? this.benefitType,
      discountPercent: clearDiscountPercent
          ? null
          : (discountPercent ?? this.discountPercent),
      price: price ?? this.price,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String _normalizeScope(String? value) {
    return value?.trim().toLowerCase() == 'global' ? 'global' : 'app';
  }

  static String _normalizeBenefitType(String? value) {
    return value?.trim().toLowerCase() == 'request_discount'
        ? 'request_discount'
        : 'free_requests';
  }

  static List<String> _parseAppIds(dynamic value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList();
    }
    return const [];
  }

  static ObjectId? _parseObjectId(dynamic value) {
    if (value is ObjectId) {
      return value;
    }
    final rawValue = value?.toString();
    if (rawValue == null || !ObjectId.isValidHexId(rawValue)) {
      return null;
    }
    return ObjectId.fromHexString(rawValue);
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is DateTime) {
      return value.toUtc();
    }
    final rawValue = value?.toString();
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    return DateTime.tryParse(rawValue)?.toUtc();
  }
}
