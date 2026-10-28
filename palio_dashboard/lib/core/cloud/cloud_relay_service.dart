import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../shared/models/obd_data_model.dart';

/// Relé de dados em tempo real entre o celular e o PC Viewer via Firestore,
/// usado quando os dois não estão na mesma rede local (o WebSocket direto
/// exige isso). O celular publica o snapshot mais recente periodicamente
/// num documento identificado por um código curto (PIN); o PC assina esse
/// documento e recebe as atualizações.
///
/// Throttla a publicação (padrão 500ms) porque o loop de PIDs roda a cada
/// ~50ms — escrever a essa frequência no Firestore estouraria a cota
/// gratuita rapidamente sem necessidade, já que o PC só precisa de uma
/// atualização visual a cada fração de segundo.
class CloudRelayService {
  CloudRelayService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestoreOverride = firestore,
      _authOverride = auth;

  // Não resolvidos no construtor — ver mesmo motivo em RemoteLogService:
  // FirebaseFirestore.instance/FirebaseAuth.instance disparam o plugin do
  // Firebase imediatamente, mesmo se este serviço nunca for usado.
  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;
  late final FirebaseFirestore _firestore =
      _firestoreOverride ?? FirebaseFirestore.instance;
  late final FirebaseAuth _auth = _authOverride ?? FirebaseAuth.instance;

  Timer? _publishTimer;
  OBDDataModel? _latest;
  String? _publishingCode;

  /// Gera um PIN criptograficamente seguro (6 dígitos) para identificar a sessão.
  static String generateCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  /// Celular: começa a publicar [update]s no documento [code] a cada
  /// [interval]. Chamar de novo com outro código troca a sessão.
  Future<void> startPublishing(
    String code, {
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    await _ensureSignedIn();
    _publishingCode = code;
    _publishTimer?.cancel();
    _publishTimer = Timer.periodic(interval, (_) => _flush());
  }

  /// Celular: atualiza o snapshot mais recente — só é de fato enviado ao
  /// Firestore no próximo tick do timer de [startPublishing].
  void update(OBDDataModel data) {
    _latest = data;
  }

  Future<void> _flush() async {
    final code = _publishingCode;
    final data = _latest;
    if (code == null || data == null) return;
    try {
      await _firestore.collection('live_sessions').doc(code).set({
        ...data.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Falha de rede pontual — tenta de novo no próximo ciclo.
    }
  }

  void stopPublishing() {
    _publishTimer?.cancel();
    _publishTimer = null;
    _publishingCode = null;
  }

  /// PC: assina o documento [code] e emite [OBDDataModel] a cada
  /// atualização recebida. Emite `disconnected` se nenhuma atualização
  /// chegar por [staleAfter] (ex.: celular fechou o app ou perdeu rede).
  Stream<OBDDataModel> subscribe(
    String code, {
    Duration staleAfter = const Duration(seconds: 15),
  }) {
    final controller = StreamController<OBDDataModel>();
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subscription;
    Timer? staleTimer;

    void armStaleTimer() {
      staleTimer?.cancel();
      staleTimer = Timer(staleAfter, () {
        controller.add(
          OBDDataModel.empty().copyWith(
            btStatus: ConnectionStatus.disconnected,
          ),
        );
      });
    }

    Future<void> begin() async {
      try {
        await _ensureSignedIn();
      } catch (_) {
        controller.add(
          OBDDataModel.empty().copyWith(
            btStatus: ConnectionStatus.disconnected,
          ),
        );
        return;
      }
      controller.add(
        OBDDataModel.empty().copyWith(btStatus: ConnectionStatus.connecting),
      );
      subscription = _firestore
          .collection('live_sessions')
          .doc(code)
          .snapshots()
          .listen(
            (snapshot) {
              final json = snapshot.data();
              if (json == null) return;
              try {
                controller.add(OBDDataModel.fromJson(json));
                armStaleTimer();
              } catch (_) {
                // Documento em formato inesperado — ignora e mantém estado.
              }
            },
            onError: (_) {
              controller.add(
                OBDDataModel.empty().copyWith(
                  btStatus: ConnectionStatus.disconnected,
                ),
              );
            },
          );
    }

    unawaited(begin());

    controller.onCancel = () {
      subscription?.cancel();
      staleTimer?.cancel();
    };

    return controller.stream;
  }

  void dispose() {
    stopPublishing();
  }
}
