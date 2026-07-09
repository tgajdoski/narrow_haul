import 'package:narrow_haul/game/services/progress_service.dart';

class CosmeticItem {
  const CosmeticItem({
    required this.id,
    required this.name,
    required this.category,
    required this.cost,
    required this.icon,
  });

  final String id;
  final String name;
  final String category;
  final int cost; // 0 means default/free
  final String icon;
}

class CosmeticsService {
  static const String catShip = 'ship';
  static const String catRope = 'rope';
  static const String catPlume = 'plume';

  static const List<CosmeticItem> all = [
    // Ships
    CosmeticItem(id: 'ship_standard', name: 'Standard', category: catShip, cost: 0, icon: '🚀'),
    CosmeticItem(id: 'ship_neon', name: 'Neon', category: catShip, cost: 100, icon: '✨'),
    CosmeticItem(id: 'ship_stealth', name: 'Stealth', category: catShip, cost: 150, icon: '🦇'),
    CosmeticItem(id: 'ship_gold', name: 'Golden Hauler', category: catShip, cost: 300, icon: '🏆'),

    // Ropes
    CosmeticItem(id: 'rope_cable', name: 'Cable', category: catRope, cost: 0, icon: '🪢'),
    CosmeticItem(id: 'rope_chain', name: 'Chain', category: catRope, cost: 80, icon: '🔗'),
    CosmeticItem(id: 'rope_energy', name: 'Energy Beam', category: catRope, cost: 200, icon: '⚡'),

    // Plumes
    CosmeticItem(id: 'plume_blue', name: 'Standard Blue', category: catPlume, cost: 0, icon: '🔥'),
    CosmeticItem(id: 'plume_green', name: 'Toxic Green', category: catPlume, cost: 50, icon: '🧪'),
    CosmeticItem(id: 'plume_red', name: 'Crimson Red', category: catPlume, cost: 50, icon: '🧨'),
    CosmeticItem(id: 'plume_rainbow', name: 'Rainbow', category: catPlume, cost: 250, icon: '🌈'),
  ];

  static bool isUnlocked(CosmeticItem item) {
    if (item.cost == 0) return true;
    return ProgressService.instance.isCosmeticUnlocked(item.id);
  }

  static Future<bool> unlock(CosmeticItem item) async {
    if (isUnlocked(item)) return true;
    final balance = ProgressService.instance.getCosmeticCurrency();
    if (balance >= item.cost) {
      await ProgressService.instance.spendCosmeticCurrency(item.cost);
      await ProgressService.instance.unlockCosmetic(item.id);
      return true;
    }
    return false;
  }

  static String getEquippedId(String category) {
    String def = '';
    if (category == catShip) def = 'ship_standard';
    if (category == catRope) def = 'rope_cable';
    if (category == catPlume) def = 'plume_blue';
    return ProgressService.instance.getEquippedCosmetic(category, def);
  }

  static Future<void> equip(CosmeticItem item) async {
    if (isUnlocked(item)) {
      await ProgressService.instance.equipCosmetic(item.category, item.id);
    }
  }
}
