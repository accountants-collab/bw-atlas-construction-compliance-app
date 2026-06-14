import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:fd_app/auth/auth_service.dart';
import 'package:fd_app/auth/auth_user.dart';

void main() {
  late Directory hiveDir;
  late AuthService service;

  const superAdminEmail = 'info@bestwaycarpentry.com';
  const superAdminPassword = String.fromEnvironment(
    'SUPER_ADMIN_PASSWORD',
    defaultValue: '9103044487Aa@',
  );

  const sessionBox = 'auth_session_box_staging';
  const dataBox = 'auth_data_box_staging';

  Future<void> resetBoxes() async {
    if (Hive.isBoxOpen(sessionBox)) {
      await Hive.box(sessionBox).close();
    }
    if (Hive.isBoxOpen(dataBox)) {
      await Hive.box(dataBox).close();
    }
    if (await Hive.boxExists(sessionBox)) {
      await Hive.deleteBoxFromDisk(sessionBox);
    }
    if (await Hive.boxExists(dataBox)) {
      await Hive.deleteBoxFromDisk(dataBox);
    }
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    hiveDir = await Directory.systemTemp.createTemp('fd_app_auth_test_');
    Hive.init(hiveDir.path);
  });

  setUp(() async {
    await resetBoxes();
    service = AuthService();
  });

  tearDown(() async {
    await resetBoxes();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  test('registration, login, invite acceptance, and seat enforcement',
      () async {
    final registered = await service.registerCompany(
      const RegisterCompanyInput(
        companyName: 'Alpha Doors Ltd',
        tradingName: 'Alpha Doors',
        address: '123 Example Road',
        adminFullName: 'Alpha Manager',
        adminEmail: 'manager@alpha.test',
        password: 'Manager#123',
        phone: '0123456789',
        seatLimit: 2,
      ),
    );

    expect(registered.user.role, UserRole.manager);

    await service.logout();
    final manager = await service.login(
        email: 'manager@alpha.test', password: 'Manager#123');
    expect(manager, isNotNull);

    final invite = await service.createInvite(
      companyId: registered.company.companyId,
      invitedName: 'Worker One',
      invitedEmail: 'worker1@alpha.test',
      invitedRole: InviteRole.worker,
      createdByUserId: manager!.id,
    );

    final accepted = await service.acceptInvite(
      token: invite.token,
      email: 'worker1@alpha.test',
      password: 'Worker#123',
    );
    expect(accepted.user.role, UserRole.worker);

    final fullSeatSummary =
        await service.getCompanySeatSummary(registered.company.companyId);
    expect(fullSeatSummary.activeUsers, 2);
    expect(fullSeatSummary.availableSeats, 0);

    await expectLater(
      () => service.createInvite(
        companyId: registered.company.companyId,
        invitedName: 'Worker Two',
        invitedEmail: 'worker2@alpha.test',
        invitedRole: InviteRole.worker,
        createdByUserId: manager.id,
      ),
      throwsA(isA<AuthFailure>()),
    );

    await service.setCompanyUserStatus(
      companyId: registered.company.companyId,
      userId: accepted.user.id,
      status: UserAccountStatus.inactive,
    );

    final freedSeatSummary =
        await service.getCompanySeatSummary(registered.company.companyId);
    expect(freedSeatSummary.activeUsers, 1);
    expect(freedSeatSummary.availableSeats, 1);

    final secondInvite = await service.createInvite(
      companyId: registered.company.companyId,
      invitedName: 'Worker Two',
      invitedEmail: 'worker2@alpha.test',
      invitedRole: InviteRole.worker,
      createdByUserId: manager.id,
    );
    expect(secondInvite.status, InviteStatus.pending);
  });

  test('super admin account is bootstrapped and can log in', () async {
    await service.restoreSession();

    final superAdmin = await service.login(
      email: superAdminEmail,
      password: superAdminPassword,
    );

    expect(superAdmin, isNotNull);
    expect(superAdmin!.role, UserRole.superAdmin);
    expect(superAdmin.isInternalAdmin, isTrue);

    final companies = await service.listAllCompanies();
    expect(companies, isNotEmpty);
  });
}
