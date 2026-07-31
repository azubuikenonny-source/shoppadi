/// What this person is allowed to do in this shop (design doc section 6).
enum ShopRole { owner, manager, cashier }

class Membership {
  const Membership({
    required this.role,
    this.businessId,
    this.canSeeProfitFlag = false,
  });

  /// The state before anyone signs in: it is your own phone and your own
  /// records, so you are the owner of them. Locking a solo shopkeeper out of
  /// their own takings because they never made an account would be absurd.
  static const solo = Membership(role: ShopRole.owner);

  final ShopRole role;
  final String? businessId;

  /// Only meaningful for managers — an owner always sees the money, a cashier
  /// never does.
  final bool canSeeProfitFlag;

  bool get isOwner => role == ShopRole.owner;
  bool get isCashier => role == ShopRole.cashier;

  /// Cost prices, profit, margins. Hiding these from cashiers is a real demand
  /// in this market, not a nicety: staff knowing the markup on every item
  /// changes how they sell it.
  bool get canSeeProfit => switch (role) {
        ShopRole.owner => true,
        ShopRole.manager => canSeeProfitFlag,
        ShopRole.cashier => false,
      };

  /// Adding stock, changing prices, correcting counts.
  bool get canManageStock => role != ShopRole.cashier;

  /// Recording expenses, taking returns, writing off damage.
  bool get canRecordMoneyOut => role != ShopRole.cashier;

  /// Inviting and removing staff, and erasing the shop.
  bool get canManageStaff => isOwner;

  String get label => switch (role) {
        ShopRole.owner => 'Owner',
        ShopRole.manager => 'Manager',
        ShopRole.cashier => 'Cashier',
      };

  static ShopRole roleFrom(String? name) => switch (name) {
        'owner' => ShopRole.owner,
        'manager' => ShopRole.manager,
        _ => ShopRole.cashier,
      };
}

/// One row of the staff list.
class StaffMember {
  const StaffMember({
    required this.userId,
    required this.name,
    required this.phone,
    required this.role,
    required this.canSeeProfit,
    required this.isMe,
  });

  final String userId;
  final String name;
  final String phone;
  final ShopRole role;
  final bool canSeeProfit;
  final bool isMe;

  /// Google accounts often carry no name, and phone sign-in carries only a
  /// number. Something has to appear in the list either way.
  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (phone.trim().isNotEmpty) return phone.trim();
    return 'Staff member';
  }
}
