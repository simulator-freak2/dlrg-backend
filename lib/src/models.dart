enum AppRole { admin, materialwart, kassenwart, vorsitz }

class User {
  User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
  });

  final String id;
  final String email;
  final String displayName;
  final AppRole role;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'role': role.name,
    };
  }
}

class InventoryItem {
  InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
  });

  final String id;
  final String name;
  final String category;
  final int quantity;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'quantity': quantity,
    };
  }
}

class ClothingItem {
  ClothingItem({
    required this.id,
    required this.name,
    required this.size,
    required this.available,
  });

  final String id;
  final String name;
  final String size;
  final bool available;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'size': size,
      'available': available,
    };
  }
}

class DocumentTemplate {
  DocumentTemplate({
    required this.id,
    required this.title,
    required this.type,
  });

  final String id;
  final String title;
  final String type;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
    };
  }
}
