import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/sync/membership.dart';

void main() {
  group('who can see the money', () {
    test('an owner always can', () {
      expect(const Membership(role: ShopRole.owner).canSeeProfit, isTrue);
    });

    test('a cashier never can, whatever the flag says', () {
      expect(
        const Membership(role: ShopRole.cashier, canSeeProfitFlag: true)
            .canSeeProfit,
        isFalse,
      );
    });

    test('a manager only when the owner allows it', () {
      expect(const Membership(role: ShopRole.manager).canSeeProfit, isFalse);
      expect(
        const Membership(role: ShopRole.manager, canSeeProfitFlag: true)
            .canSeeProfit,
        isTrue,
      );
    });
  });

  group('what each role can change', () {
    test('cashiers sell but do not touch stock or money out', () {
      const cashier = Membership(role: ShopRole.cashier);
      expect(cashier.canManageStock, isFalse);
      expect(cashier.canRecordMoneyOut, isFalse);
      expect(cashier.canManageStaff, isFalse);
    });

    test('managers run the shop but not the team', () {
      const manager = Membership(role: ShopRole.manager);
      expect(manager.canManageStock, isTrue);
      expect(manager.canRecordMoneyOut, isTrue);
      expect(manager.canManageStaff, isFalse);
    });

    test('owners can do everything', () {
      const owner = Membership(role: ShopRole.owner);
      expect(owner.canManageStock, isTrue);
      expect(owner.canRecordMoneyOut, isTrue);
      expect(owner.canManageStaff, isTrue);
    });
  });

  group('a phone nobody has signed into', () {
    test('answers to itself — its records are its own', () {
      expect(Membership.solo.canSeeProfit, isTrue);
      expect(Membership.solo.canManageStock, isTrue);
      expect(Membership.solo.isOwner, isTrue);
    });
  });

  group('roles off the wire', () {
    test('known names map through', () {
      expect(Membership.roleFrom('owner'), ShopRole.owner);
      expect(Membership.roleFrom('manager'), ShopRole.manager);
      expect(Membership.roleFrom('cashier'), ShopRole.cashier);
    });

    test('anything unrecognised lands on the least privilege', () {
      expect(Membership.roleFrom(null), ShopRole.cashier);
      expect(Membership.roleFrom(''), ShopRole.cashier);
      expect(Membership.roleFrom('administrator'), ShopRole.cashier);
    });
  });

  group('naming a staff member', () {
    StaffMember member({String name = '', String phone = ''}) => StaffMember(
          userId: 'u1',
          name: name,
          phone: phone,
          role: ShopRole.cashier,
          canSeeProfit: false,
          isMe: false,
        );

    test('prefers the name', () {
      expect(member(name: 'Chidinma', phone: '0803').displayName, 'Chidinma');
    });

    test('falls back to the phone when Google gave no name', () {
      expect(member(phone: '08031234567').displayName, '08031234567');
    });

    test('never renders blank', () {
      expect(member().displayName, 'Staff member');
      expect(member(name: '   ').displayName, 'Staff member');
    });
  });
}
