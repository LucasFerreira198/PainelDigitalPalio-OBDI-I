import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:palio_dashboard/core/ota/ota_provider.dart';
import 'package:palio_dashboard/core/ota/ota_service.dart';
import 'package:palio_dashboard/features/dashboard/dashboard_provider.dart';
import 'package:palio_dashboard/features/settings/settings_provider.dart';
import 'package:palio_dashboard/features/settings/settings_screen.dart';
import 'package:palio_dashboard/main.dart';
import 'package:palio_dashboard/shared/models/obd_data_model.dart';

class _NoUpdateOtaService extends OtaService {
  @override
  Future<OtaUpdateInfo?> checkForUpdate() async => null;
}

void main() {
  testWidgets('PalioDash renders dashboard without crashing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          obdDataProvider.overrideWith(
            (ref) => Stream.value(OBDDataModel.empty()),
          ),
          otaServiceProvider.overrideWithValue(_NoUpdateOtaService()),
        ],
        child: const PalioDashApp(),
      ),
    );
    await tester.pump();
    // Deixa o timer de checagem automática de OTA (5s) disparar e resolver.
    await tester.pump(const Duration(seconds: 6));

    expect(find.text('RPM'), findsOneWidget);
  });

  testWidgets(
    'Dashboard exibe banner de shift light quando RPM atinge o limite',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            obdDataProvider.overrideWith(
              (ref) => Stream.value(
                OBDDataModel.empty().copyWith(
                  rpm: 6200.0,
                ),
              ),
            ),
            otaServiceProvider.overrideWithValue(_NoUpdateOtaService()),
          ],
          child: const PalioDashApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));

      expect(
        find.textContaining('SHIFT LIGHT'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Dashboard não estoura layout em tela pequena (800x480) com botão de ECU visível',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            obdDataProvider.overrideWith(
              (ref) => Stream.value(
                OBDDataModel.empty().copyWith(
                  btStatus: ConnectionStatus.connected,
                  ecuResponding: false,
                ),
              ),
            ),
            otaServiceProvider.overrideWithValue(_NoUpdateOtaService()),
          ],
          child: const PalioDashApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));

      // Com OBD2 conectado e ECU não respondendo, o botão "Conectar à ECU"
      // aparece — os ícones de DTC/Configurações devem continuar visíveis
      // ao lado dele, sem estourar o layout (RenderFlex overflow).
      expect(find.text('Conectar à ECU'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('SettingsScreen carrega seções de perfil e customização', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bondedDevicesProvider.overrideWith((ref) => Future.value([])),
          localIpProvider.overrideWith((ref) => Future.value(null)),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Configurações do Painel'), findsOneWidget);
    expect(find.text('Veículo & Injeção Eletrônica'), findsOneWidget);
    expect(find.text('Tema Visual dos Instrumentos'), findsOneWidget);
    expect(find.text('Alertas & Avisos de Segurança'), findsOneWidget);
  });
}
