// Этот файл: lib/src/models/transaction.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

import 'package:mongo_dart/mongo_dart.dart';

/// Transaction type enum
enum TransactionType { deposit, withdrawal, payment }

/// Transaction model
class Transaction {
  final ObjectId? id;
  final ObjectId userId;
  final String? userName;
  final double amount;
  final TransactionType type;
  final String? description;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  /// Конструктор Transaction: создаёт новый объект этого класса.
  /// Возвращает готовый объект, с которым дальше работает приложение.
  Transaction({
    this.id,
    required this.userId,
    this.userName,
    required this.amount,
    required this.type,
    this.description,
    this.metadata,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// From JSON
  factory Transaction.fromJson(Map<String, dynamic> json) {
    /// Функция Transaction: выполняет шаг Transaction в этой части программы. Возвращает значение типа return; это готовый результат для следующего шага программы.
    /// Возвращает значение типа return; это готовый результат для следующего шага программы.
    return Transaction(
      id: json['_id'] as ObjectId?,
      userId: json['userId'] as ObjectId,
      userName: json['userName'] as String?,
      amount: (json['amount'] as num).toDouble(),
      type: TransactionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TransactionType.deposit,
      ),
      description: json['description'] as String?,
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  /// To JSON
  Map<String, dynamic> toJson() {
    return {
      if (id != null) '_id': id,
      'userId': userId,
      if (userName != null) 'userName': userName,
      'amount': amount,
      'type': type.name,
      if (description != null) 'description': description,
      if (metadata != null) 'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// To public JSON
  Map<String, dynamic> toPublicJson() {
    return {
      '_id': id?.oid,
      'userId': userId.oid,
      if (userName != null) 'userName': userName,
      'amount': amount,
      'type': type.name,
      if (description != null) 'description': description,
      if (metadata != null) 'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
