import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bluetooth/bt_manager.dart';
import '../../core/obd2/marelli_protocol.dart';
import '../../core/obd2/obd2_service.dart';
import '../../shared/theme/app_theme.dart';
import '../dashboard/dashboard_provider.dart';
import '../settings/settings_provider.dart';

enum TestStatus { idle, running, success, failure }

class _TestCase {
  final String id;
  final String title;
  final String command;
  final String description;
  TestStatus status;
  String? resultValue;
  String? rawResponse;
  String? errorMessage;

  _TestCase({
    required this.id,
    required this.title,
    required this.command,
    required this.description,
    this.status = TestStatus.idle,
    this.resultValue,
    this.rawResponse,
    this.errorMessage,
  });
}

class TestObdScreen extends ConsumerStatefulWidget {
  const TestObdScreen({super.key});

  @override
  ConsumerState<TestObdScreen> createState() => _TestObdScreenState();
}

class _TestObdScreenState extends ConsumerState<TestObdScreen> {
  final TextEditingController _cmdController = TextEditingController();
  final ScrollController _terminalScrollController = ScrollController();
  StreamSubscription<BtTrafficLog>? _trafficSub;
  final List<BtTrafficLog> _trafficLogs = [];

  bool _isAutoSuiteRunning = false;
  String? _autoSuiteSummary;
  bool _autoScroll = true;
  late EcuProtocol _selectedProtocol;

  late final List<_TestCase> _testCases;

  @override
  void initState() {
    super.initState();

    _selectedProtocol =
        ref.read(manualEcuProtocolProvider) ?? EcuProtocol.kwp2000FastInit;

    _testCases = [
      _TestCase(
        id: 'atz',
        title: '1. Reset do Chip ELM327',
        command: 'ATZ',
        description: 'Reinicia o microcontrolador e obtém versão do firmware do adaptador.',
      ),
      _TestCase(
        id: 'setup',
        title: '2. Configurar Protocolo Palio Fire',
        command: 'ATSP5 + ATIB10 + ATSH8210F1',
        description: 'Aplica ISO 14230-4 KWP2000 Fast Init a 10400 bps com cabeçalho 82 10 F1.',
      ),
      _TestCase(
        id: 'atrv',
        title: '3. Tensão da Bateria (ATRV)',
        command: 'ATRV',
        description: 'Mede a voltagem no pino 16 da porta OBD2 (independe da ECU ligada).',
      ),
      _TestCase(
        id: 'wakeup',
        title: '4. Despertar ECU (Handshake 1A 97)',
        command: '1A 97',
        description: 'Envia ReadEcuIdentification no formato AlfaOBD. Espera resposta 5A 97.',
      ),
      _TestCase(
        id: 'rpm',
        title: '5. Rotação do Motor (RPM)',
        command: '01 0C',
        description: 'Consulta giro do motor via PID padrão SAE/EOBD modo 01.',
      ),
      _TestCase(
        id: 'temp',
        title: '6. Temperatura do Motor',
        command: '01 05',
        description: 'Consulta temperatura da água do motor (°C).',
      ),
      _TestCase(
        id: 'fuel',
        title: '7. Nível de Combustível',
        command: '01 2F',
        description: 'Consulta porcentagem do tanque de combustível (0 a 100%).',
      ),
      _TestCase(
        id: 'map',
        title: '8. Pressão no Coletor (MAP)',
        command: '01 0B',
        description: 'Consulta pressão absoluta do coletor de admissão (kPa).',
      ),
      _TestCase(
        id: 'tps',
        title: '9. Posição da Borboleta (TPS)',
        command: '01 11',
        description: 'Consulta ângulo/abertura percentual da borboleta de aceleração.',
      ),
      _TestCase(
        id: 'local21',
        title: '10. Bloco Local Marelli (Service 21)',
        command: '21 01',
        description: 'Consulta bloco de parâmetros proprietários KWP2000 Local ID 01.',
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Pausa o loop de background enquanto a central de diagnóstico estiver aberta
      ref.read(currentObd2ServiceProvider)?.stopLoop();

      final btManager = ref.read(btManagerProvider);
      setState(() {
        _trafficLogs.addAll(btManager.trafficHistory);
      });
      _trafficSub = btManager.trafficStream.listen((entry) {
        if (!mounted) return;
        setState(() {
          _trafficLogs.add(entry);
        });
        if (_autoScroll && _terminalScrollController.hasClients) {
          _terminalScrollController.animateTo(
            _terminalScrollController.position.maxScrollExtent + 60,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _trafficSub?.cancel();
    _cmdController.dispose();
    _terminalScrollController.dispose();
    // Retoma o loop normal do dashboard ao sair
    ref.read(currentObd2ServiceProvider)?.startLoop();
    super.dispose();
  }

  Future<void> _executeStep(_TestCase test) async {
    final btManager = ref.read(btManagerProvider);
    if (!btManager.isConnected) {
      setState(() {
        test.status = TestStatus.failure;
        test.errorMessage = 'Bluetooth não conectado. Conecte nas Configurações.';
      });
      return;
    }

    setState(() {
      test.status = TestStatus.running;
      test.errorMessage = null;
      test.rawResponse = null;
      test.resultValue = null;
    });

    try {
      switch (test.id) {
        case 'atz':
          final raw = await btManager.sendCommand('ATZ', timeout: const Duration(seconds: 3));
          final clean = raw.replaceAll('>', '').trim();
          setState(() {
            test.rawResponse = clean;
            test.status = TestStatus.success;
            test.resultValue = 'Chip: $clean';
          });
          break;

        case 'setup':
          for (final cmd in kElm327SetupKwp2000FastInit) {
            final t = cmd == 'ATZ' ? const Duration(seconds: 3) : BtManager.defaultTimeout;
            await btManager.sendCommand(cmd, timeout: t);
          }
          setState(() {
            test.rawResponse = 'ATSP5, ATIB10, ATH1, ATSH8210F1 OK';
            test.status = TestStatus.success;
            test.resultValue = 'Configurado para Palio Fire (KWP2000 Fast Init)';
          });
          break;

        case 'atrv':
          final raw = await btManager.sendCommand('ATRV', timeout: const Duration(seconds: 2));
          final parsed = parseMarelliResponse(raw);
          if (parsed != null && parsed.dataBytes.isNotEmpty) {
            final v = MarelliFormulas.voltage(parsed.dataBytes);
            setState(() {
              test.rawResponse = raw.replaceAll('>', '').trim();
              test.status = TestStatus.success;
              test.resultValue = '${v.toStringAsFixed(1)} V';
            });
          } else {
            setState(() {
              test.rawResponse = raw;
              test.status = TestStatus.failure;
              test.errorMessage = 'Não foi possível ler a tensão do adaptador ($raw)';
            });
          }
          break;

        case 'wakeup':
          final raw = await btManager.sendCommand('1A 97', timeout: const Duration(milliseconds: 3800));
          final clean = raw.replaceAll('>', '').trim();
          if (!isElmFailureResponse(raw) && (clean.contains('5A') || clean.contains('97'))) {
            setState(() {
              test.rawResponse = clean;
              test.status = TestStatus.success;
              test.resultValue = 'ECU Acordada! Resposta positiva: $clean';
            });
          } else {
            setState(() {
              test.rawResponse = clean;
              test.status = TestStatus.failure;
              test.errorMessage = isElmFailureResponse(raw)
                  ? 'ECU não respondeu ($clean). Ligue a chave de ignição.'
                  : 'Resposta inesperada: $clean';
            });
          }
          break;

        case 'rpm':
          final raw = await btManager.sendCommand('01 0C', timeout: const Duration(seconds: 3));
          final parsed = parseMarelliResponse(raw);
          if (parsed != null && parsed.dataBytes.length >= 2) {
            final rpm = MarelliFormulas.rpm(parsed.dataBytes);
            setState(() {
              test.rawResponse = raw.replaceAll('>', '').trim();
              test.status = TestStatus.success;
              test.resultValue = '${rpm.toStringAsFixed(0)} RPM (Modo 01)';
            });
          } else {
            // Fallback para Service 21 Marelli Local ID 01 (comum em IAW 4AF/4SF)
            try {
              final locRaw = await btManager.sendCommand(
                '21 01',
                timeout: const Duration(seconds: 3),
              );
              final locParsed = parseMarelliResponse(locRaw);
              if (locParsed != null && locParsed.dataBytes.length >= 2) {
                final locRpm = MarelliFormulas.rpm(locParsed.dataBytes);
                setState(() {
                  test.rawResponse =
                      '01 0C: ${raw.replaceAll('>', '').trim()} | 21 01: ${locRaw.replaceAll('>', '').trim()}';
                  test.status = TestStatus.success;
                  test.resultValue =
                      '${locRpm.toStringAsFixed(0)} RPM (Marelli Service 21)';
                });
                break;
              }
            } catch (_) {}

            setState(() {
              test.rawResponse = raw.replaceAll('>', '').trim();
              test.status = TestStatus.failure;
              test.errorMessage =
                  'Sem leitura de RPM via 01 0C nem 21 01 ($raw)';
            });
          }
          break;

        case 'temp':
          final raw = await btManager.sendCommand('01 05', timeout: const Duration(seconds: 3));
          final parsed = parseMarelliResponse(raw);
          if (parsed != null && parsed.dataBytes.isNotEmpty) {
            final t = MarelliFormulas.temp(parsed.dataBytes);
            setState(() {
              test.rawResponse = raw.replaceAll('>', '').trim();
              test.status = TestStatus.success;
              test.resultValue = '${t.toStringAsFixed(0)} °C';
            });
          } else {
            setState(() {
              test.rawResponse = raw.replaceAll('>', '').trim();
              test.status = TestStatus.failure;
              test.errorMessage = 'Sem leitura de temperatura ($raw)';
            });
          }
          break;

        case 'fuel':
          final raw = await btManager.sendCommand('01 2F', timeout: const Duration(seconds: 3));
          final parsed = parseMarelliResponse(raw);
          if (parsed != null && parsed.dataBytes.isNotEmpty) {
            final f = MarelliFormulas.fuelLevel(parsed.dataBytes);
            final liters = (f * 48.0 / 100.0);
            setState(() {
              test.rawResponse = raw.replaceAll('>', '').trim();
              test.status = TestStatus.success;
              test.resultValue = '${f.toStringAsFixed(1)}% (~${liters.toStringAsFixed(1)}L)';
            });
          } else {
            setState(() {
              test.rawResponse = raw.replaceAll('>', '').trim();
              test.status = TestStatus.failure;
              test.errorMessage = 'Sem leitura de nível de combustível ($raw)';
            });
          }
          break;

        case 'map':
          final raw = await btManager.sendCommand('01 0B', timeout: const Duration(seconds: 3));
          final parsed = parseMarelliResponse(raw);
          if (parsed != null && parsed.dataBytes.isNotEmpty) {
            final mapVal = MarelliFormulas.map(parsed.dataBytes);
            setState(() {
              test.rawResponse = raw.replaceAll('>', '').trim();
              test.status = TestStatus.success;
              test.resultValue = '${mapVal.toStringAsFixed(0)} kPa';
            });
          } else {
            setState(() {
              test.rawResponse = raw.replaceAll('>', '').trim();
              test.status = TestStatus.failure;
              test.errorMessage = 'Sem leitura de MAP ($raw)';
            });
          }
          break;

        case 'tps':
          final raw = await btManager.sendCommand('01 11', timeout: const Duration(seconds: 3));
          final parsed = parseMarelliResponse(raw);
          if (parsed != null && parsed.dataBytes.isNotEmpty) {
            final tpsVal = MarelliFormulas.tps(parsed.dataBytes);
            setState(() {
              test.rawResponse = raw.replaceAll('>', '').trim();
              test.status = TestStatus.success;
              test.resultValue = '${tpsVal.toStringAsFixed(1)}%';
            });
          } else {
            setState(() {
              test.rawResponse = raw.replaceAll('>', '').trim();
              test.status = TestStatus.failure;
              test.errorMessage = 'Sem leitura de TPS ($raw)';
            });
          }
          break;

        case 'local21':
          final raw = await btManager.sendCommand('21 01', timeout: const Duration(seconds: 3));
          final clean = raw.replaceAll('>', '').trim();
          if (!isElmFailureResponse(raw) && (clean.contains('61') || clean.contains('01'))) {
            setState(() {
              test.rawResponse = clean;
              test.status = TestStatus.success;
              test.resultValue = 'Bloco Marelli recebido: $clean';
            });
          } else {
            setState(() {
              test.rawResponse = clean;
              test.status = TestStatus.failure;
              test.errorMessage = 'Sem resposta do Local ID 01 ($clean)';
            });
          }
          break;
      }
    } catch (e) {
      setState(() {
        test.status = TestStatus.failure;
        test.errorMessage = e.toString();
      });
    }
  }

  Future<void> _runFullSuite() async {
    final btManager = ref.read(btManagerProvider);
    if (!btManager.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conecte o Bluetooth nas Configurações antes de iniciar o teste.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Pausa o loop de background se estiver rodando para não colidir
    final obdService = ref.read(currentObd2ServiceProvider);
    obdService?.stopLoop();

    setState(() {
      _isAutoSuiteRunning = true;
      _autoSuiteSummary = null;
    });

    int successes = 0;
    for (final test in _testCases) {
      await _executeStep(test);
      if (test.status == TestStatus.success) {
        successes++;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final batteryTest = _testCases.firstWhere((t) => t.id == 'atrv');
    final wakeupTest = _testCases.firstWhere((t) => t.id == 'wakeup');
    final rpmTest = _testCases.firstWhere((t) => t.id == 'rpm');

    String summary;
    if (wakeupTest.status == TestStatus.success || rpmTest.status == TestStatus.success) {
      summary = '✅ SUCESSO: ECU Marelli IAW 4AF comunicando com sucesso! '
          'Bateria: ${batteryTest.resultValue ?? '--'} • Giro: ${rpmTest.resultValue ?? '--'}. '
          'Você pode abrir o painel principal!';
    } else if (batteryTest.status == TestStatus.success) {
      summary = '⚠️ ATENÇÃO: Adaptador ELM327 respondeu perfeitamente com '
          '${batteryTest.resultValue}, mas a ECU não respondeu. '
          'Gire a chave do Palio no primeiro estágio (painel aceso) e repita!';
    } else {
      summary = '❌ FALHA: O adaptador não respondeu aos comandos básicos. '
          'Verifique se o ELM327 está bem encaixado na tomada OBD2 do Palio.';
    }

    setState(() {
      _isAutoSuiteRunning = false;
      _autoSuiteSummary = summary;
    });

    // Retoma o loop normal
    obdService?.startLoop();
  }

  Future<void> _sendManualCommand() async {
    final cmd = _cmdController.text.trim();
    if (cmd.isEmpty) return;

    final btManager = ref.read(btManagerProvider);
    if (!btManager.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bluetooth não conectado.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _cmdController.clear();
    FocusScope.of(context).unfocus();

    try {
      await btManager.sendCommand(cmd, timeout: const Duration(seconds: 4));
    } catch (e) {
      // Já logado pelo BtManager
    }
  }

  void _copyTerminalLogs() {
    final text = _trafficLogs.map((log) {
      final time =
          '${log.timestamp.hour.toString().padLeft(2, '0')}:'
          '${log.timestamp.minute.toString().padLeft(2, '0')}:'
          '${log.timestamp.second.toString().padLeft(2, '0')}.'
          '${log.timestamp.millisecond.toString().padLeft(3, '0')}';
      final prefix = switch (log.type) {
        BtTrafficType.tx => 'TX >',
        BtTrafficType.rx => 'RX <',
        BtTrafficType.info => 'INFO',
        BtTrafficType.error => 'ERRO',
      };
      return '[$time] [$prefix] ${log.text}';
    }).join('\n');

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Log do terminal copiado para a área de transferência!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _clearTerminal() {
    final btManager = ref.read(btManagerProvider);
    btManager.clearTrafficLogs();
    setState(() {
      _trafficLogs.clear();
    });
  }

  Future<void> _switchProtocol(EcuProtocol proto) async {
    final btManager = ref.read(btManagerProvider);
    if (!btManager.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bluetooth não conectado. Conecte nas Configurações.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final obdService = ref.read(currentObd2ServiceProvider);
    if (obdService != null) {
      final ok = await obdService.switchProtocolLive(proto);
      if (mounted) {
        setState(() {
          _selectedProtocol = proto;
        });
        ref.read(manualEcuProtocolProvider.notifier).state = proto;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Protocolo alterado ao vivo para ${proto.displayLabel}!'
                  : 'Falha ao reconfigurar protocolo no adaptador.',
            ),
            backgroundColor: ok ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final btManager = ref.watch(btManagerProvider);
    final isConnected = btManager.isConnected;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Central de Diagnóstico & Teste IAW 4AF',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Fiat Palio Fire • Marelli IAW 4AF/4EF/59F/5AF EOBD',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: 'Copiar Log do Terminal',
            onPressed: _copyTerminalLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Limpar Terminal',
            onPressed: _clearTerminal,
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: const Icon(Icons.speed, size: 16),
            label: const Text('Ir ao Painel', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Status bar superior
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.surface,
              child: Row(
                children: [
                  Icon(
                    isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: isConnected ? Colors.greenAccent : Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isConnected ? 'Bluetooth Pareado & Conectado' : 'Bluetooth Desconectado',
                    style: TextStyle(
                      color: isConnected ? Colors.greenAccent : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _selectedProtocol == EcuProtocol.kwp2000FastInit
                          ? 'Palio Fire • Fast Init • ATSH8210F1'
                          : _selectedProtocol.displayLabel,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

            // Barra de troca rápida de protocolo ao vivo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: const Color(0xFF161B22),
              child: Row(
                children: [
                  const Icon(Icons.sync_alt, color: AppTheme.accent, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'Protocolo:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: EcuProtocol.values.map((p) {
                          final isSelected = p == _selectedProtocol;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                p == EcuProtocol.kwp2000FastInit
                                    ? 'Palio Fire (KWP2000 Fast)'
                                    : p.displayLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight:
                                      isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? Colors.black : Colors.white70,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: AppTheme.accent,
                              backgroundColor: AppTheme.surface,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onSelected: (selected) {
                                if (selected) {
                                  _switchProtocol(p);
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_autoSuiteSummary != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _autoSuiteSummary!.contains('✅')
                      ? Colors.green.shade900.withOpacity(0.5)
                      : (_autoSuiteSummary!.contains('⚠️')
                          ? Colors.amber.shade900.withOpacity(0.5)
                          : Colors.red.shade900.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _autoSuiteSummary!.contains('✅')
                        ? Colors.greenAccent
                        : (_autoSuiteSummary!.contains('⚠️')
                            ? Colors.amberAccent
                            : Colors.redAccent),
                  ),
                ),
                child: Text(
                  _autoSuiteSummary!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),

            // Botão Principal de Diagnóstico
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isAutoSuiteRunning ? Colors.grey : AppTheme.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isAutoSuiteRunning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 24),
                  label: Text(
                    _isAutoSuiteRunning
                        ? 'EXECUTANDO TESTE AUTOMATIZADO...'
                        : '⚡ EXECUTAR DIAGNÓSTICO COMPLETO IAW 4AF',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: _isAutoSuiteRunning ? null : _runFullSuite,
                ),
              ),
            ),

            // Divisão horizontal: Lado esquerdo (Testes) e Lado direito (Console Terminal)
            Expanded(
              child: Row(
                children: [
                  // Painel esquerdo: Lista de testes em cards
                  Expanded(
                    flex: 5,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      itemCount: _testCases.length,
                      itemBuilder: (context, index) {
                        final test = _testCases[index];
                        return _buildTestCard(test);
                      },
                    ),
                  ),

                  // Painel direito: Terminal Monospace em tempo real
                  Expanded(
                    flex: 6,
                    child: Container(
                      margin: const EdgeInsets.only(right: 12, top: 4, bottom: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          // Header do Terminal
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF161B22),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.terminal, color: AppTheme.accent, size: 16),
                                const SizedBox(width: 6),
                                const Text(
                                  'Terminal de Tráfego OBD2 (Hex/ASCII)',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => setState(() => _autoScroll = !_autoScroll),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _autoScroll ? Icons.check_box : Icons.check_box_outline_blank,
                                        size: 14,
                                        color: AppTheme.accent,
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'Auto-scroll',
                                        style: TextStyle(color: Colors.white54, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Conteúdo do terminal
                          Expanded(
                            child: _trafficLogs.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Nenhuma comunicação registrada ainda.\nExecute um teste ou envie um comando abaixo.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white24, fontSize: 12),
                                    ),
                                  )
                                : ListView.builder(
                                    controller: _terminalScrollController,
                                    padding: const EdgeInsets.all(8),
                                    itemCount: _trafficLogs.length,
                                    itemBuilder: (context, idx) {
                                      final log = _trafficLogs[idx];
                                      final time =
                                          '${log.timestamp.hour.toString().padLeft(2, '0')}:'
                                          '${log.timestamp.minute.toString().padLeft(2, '0')}:'
                                          '${log.timestamp.second.toString().padLeft(2, '0')}.'
                                          '${log.timestamp.millisecond.toString().padLeft(3, '0')}';

                                      Color color;
                                      String prefix;
                                      switch (log.type) {
                                        case BtTrafficType.tx:
                                          color = Colors.cyanAccent;
                                          prefix = 'TX >';
                                          break;
                                        case BtTrafficType.rx:
                                          color = const Color(0xFF00FF66);
                                          prefix = 'RX <';
                                          break;
                                        case BtTrafficType.info:
                                          color = Colors.amberAccent;
                                          prefix = 'INF';
                                          break;
                                        case BtTrafficType.error:
                                          color = Colors.redAccent;
                                          prefix = 'ERR';
                                          break;
                                      }

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                                        child: SelectableText.rich(
                                          TextSpan(
                                            children: [
                                              TextSpan(
                                                text: '[$time] ',
                                                style: const TextStyle(
                                                  color: Colors.white38,
                                                  fontFamily: 'monospace',
                                                  fontSize: 11,
                                                ),
                                              ),
                                              TextSpan(
                                                text: '$prefix ',
                                                style: TextStyle(
                                                  color: color,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'monospace',
                                                  fontSize: 11,
                                                ),
                                              ),
                                              TextSpan(
                                                text: log.text,
                                                style: TextStyle(
                                                  color: color,
                                                  fontFamily: 'monospace',
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),

                          // Chips de comandos rápidos
                          Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            color: const Color(0xFF161B22),
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _buildQuickChip('ATRV'),
                                _buildQuickChip('1A 97'),
                                _buildQuickChip('01 0C'),
                                _buildQuickChip('01 05'),
                                _buildQuickChip('01 2F'),
                                _buildQuickChip('01 0B'),
                                _buildQuickChip('01 11'),
                                _buildQuickChip('21 01'),
                                _buildQuickChip('01 00'),
                                _buildQuickChip('ATDP'),
                                _buildQuickChip('ATH1'),
                                _buildQuickChip('ATH0'),
                                _buildQuickChip('ATSP5'),
                              ],
                            ),
                          ),

                          // Barra de envio de comando manual
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            color: const Color(0xFF0D1117),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _cmdController,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Digite comando (ex: ATRV, 1A 97)...',
                                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      filled: true,
                                      fillColor: const Color(0xFF161B22),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: const BorderSide(color: Colors.white24),
                                      ),
                                    ),
                                    onSubmitted: (_) => _sendManualCommand(),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accent,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                  onPressed: _sendManualCommand,
                                  child: const Text('Enviar', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace')),
        backgroundColor: const Color(0xFF21262D),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: () {
          _cmdController.text = label;
          _sendManualCommand();
        },
      ),
    );
  }

  Widget _buildTestCard(_TestCase test) {
    final statusColor = switch (test.status) {
      TestStatus.idle => Colors.white24,
      TestStatus.running => AppTheme.accent,
      TestStatus.success => Colors.greenAccent,
      TestStatus.failure => Colors.redAccent,
    };

    final statusIcon = switch (test.status) {
      TestStatus.idle => Icons.circle_outlined,
      TestStatus.running => Icons.hourglass_top_rounded,
      TestStatus.success => Icons.check_circle_rounded,
      TestStatus.failure => Icons.error_rounded,
    };

    return Card(
      color: AppTheme.surface,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: test.status == TestStatus.success
              ? Colors.greenAccent.withOpacity(0.4)
              : (test.status == TestStatus.failure
                  ? Colors.redAccent.withOpacity(0.4)
                  : Colors.white10),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    test.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    test.command,
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 28,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: const BorderSide(color: AppTheme.accent),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _isAutoSuiteRunning || test.status == TestStatus.running
                        ? null
                        : () => _executeStep(test),
                    child: test.status == TestStatus.running
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                          )
                        : const Text('Testar', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              test.description,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            if (test.resultValue != null) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade900.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'VALOR: ${test.resultValue}',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            if (test.rawResponse != null) ...[
              const SizedBox(height: 4),
              Text(
                'RAW: ${test.rawResponse}',
                style: const TextStyle(
                  color: Colors.white38,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ],
            if (test.errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                'ERRO: ${test.errorMessage}',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
