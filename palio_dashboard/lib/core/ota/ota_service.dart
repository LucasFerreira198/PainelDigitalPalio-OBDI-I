import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const String githubOwner = 'LucasFerreira198';
const String githubRepo = 'PainelDigitalPalio-OBDI-I';

class OtaUpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;

  const OtaUpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
  });
}

/// Verifica e baixa atualizações via GitHub Releases. Nunca instala
/// automaticamente — sempre depende de confirmação explícita do usuário
/// antes de baixar/abrir o APK.
class OtaService {
  final Dio _dio;

  OtaService({Dio? dio}) : _dio = dio ?? Dio();

  /// Consulta a release mais recente e retorna [OtaUpdateInfo] se houver uma
  /// versão mais nova disponível, ou null se o app já está atualizado.
  Future<OtaUpdateInfo?> checkForUpdate() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest',
    );
    final body = response.data;
    if (body == null) return null;

    final tagName = body['tag_name'] as String?;
    if (tagName == null) return null;

    final assets = (body['assets'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final apkAsset = assets.firstWhere(
      (asset) => (asset['name'] as String?)?.endsWith('.apk') ?? false,
      orElse: () => const {},
    );
    final downloadUrl = apkAsset['browser_download_url'] as String?;
    if (downloadUrl == null) return null;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    if (!isNewerVersion(latest: tagName, current: currentVersion)) {
      return null;
    }

    return OtaUpdateInfo(
      latestVersion: tagName,
      currentVersion: currentVersion,
      downloadUrl: downloadUrl,
    );
  }

  /// Baixa o APK em [getTemporaryDirectory]/update.apk, reportando progresso
  /// de 0.0 a 1.0 via [onProgress].
  /// Valida estritamente a URL de download para mitigar ataques de spoofing/MITM.
  Future<String> downloadApk(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      throw ArgumentError('URL de atualização inválida: deve usar protocolo HTTPS.');
    }

    final host = uri.host.toLowerCase();
    final isAllowedHost = host == 'github.com' ||
        host.endsWith('.github.com') ||
        host == 'objects.githubusercontent.com' ||
        host.endsWith('.githubusercontent.com');

    if (!isAllowedHost) {
      throw ArgumentError('URL de atualização não autorizada: origem fora do GitHub ($host).');
    }

    if (!uri.path.toLowerCase().endsWith('.apk')) {
      throw ArgumentError('Arquivo de atualização inválido: deve possuir extensão .apk.');
    }

    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/update.apk';

    await _dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );

    return savePath;
  }
}

/// Compara versões semver (ex.: "v1.2.0" vs "1.1.5"). Ignora prefixo "v" e
/// sufixos de build (+N). Retorna true se [latest] for maior que [current].
bool isNewerVersion({required String latest, required String current}) {
  final latestParts = _parseSemver(latest);
  final currentParts = _parseSemver(current);

  for (var i = 0; i < 3; i++) {
    if (latestParts[i] != currentParts[i]) {
      return latestParts[i] > currentParts[i];
    }
  }
  return false;
}

List<int> _parseSemver(String version) {
  final cleaned = version.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');
  final withoutBuild = cleaned.split('+').first;
  final segments = withoutBuild.split('.');
  return List.generate(3, (i) {
    if (i >= segments.length) return 0;
    return int.tryParse(segments[i]) ?? 0;
  });
}
