import 'models.dart';

class AppRepository {
  final List<User> _users = [
    User(
      id: 'u1',
      email: 'admin@dlrg.local',
      displayName: 'Admin',
      role: AppRole.admin,
    ),
    User(
      id: 'u2',
      email: 'material@dlrg.local',
      displayName: 'Materialwart',
      role: AppRole.materialwart,
    ),
  ];

  final List<InventoryItem> _inventory = [
    InventoryItem(id: 'i1', name: 'Rettungsring', category: 'Sicherheit', quantity: 5),
    InventoryItem(id: 'i2', name: 'Erste-Hilfe-Set', category: 'Medizin', quantity: 12),
  ];

  final List<ClothingItem> _clothing = [
    ClothingItem(id: 'c1', name: 'Dienstjacke', size: 'L', available: true),
    ClothingItem(id: 'c2', name: 'Poloshirt', size: 'M', available: false),
  ];

  final List<DocumentTemplate> _documents = [
    DocumentTemplate(id: 'd1', title: 'Einladung zur Vorstandssitzung', type: 'einladung'),
    DocumentTemplate(id: 'd2', title: 'Dienstanweisung Einsatzdienst', type: 'dienstanweisung'),
  ];

  List<User> users() => List.unmodifiable(_users);
  List<InventoryItem> inventory() => List.unmodifiable(_inventory);
  List<ClothingItem> clothing() => List.unmodifiable(_clothing);
  List<DocumentTemplate> documentTemplates() => List.unmodifiable(_documents);
}
