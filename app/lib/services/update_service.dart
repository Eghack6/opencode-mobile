import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final String? error;

  UpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.downloadUrl,
    this.releaseNotes,
    this.error,
  });
}

class UpdateService {
  static const String _repo = 'Eghack6/opencode-mobile';
  static const String _apiUrl = 'https://api.github.com/repos/$_repo/releases/latest';

  Future<UpdateInfo> checkForUpdate() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final currentVersion = pkg.version;

      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'opencode-mobile/1.0',
        },
      );

      if (response.statusCode == 404) {
        return UpdateInfo(
          hasUpdate: false,
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          error: '暂未发布正式版本，暂无更新',
        );
      }

      if (response.statusCode == 403) {
        return UpdateInfo(
          hasUpdate: false,
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          error: 'GitHub API 访问频率受限，请稍后再试',
        );
      }

      if (response.statusCode != 200) {
        return UpdateInfo(
          hasUpdate: false,
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          error: '检查更新失败 ($response.statusCode)，请检查网络或挂载代理后重试',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latestTag = data['tag_name'] as String? ?? '';
      final latestVersion = latestTag.replaceAll(RegExp(r'^v'), '');
      final body = data['body'] as String?;
      final assets = data['assets'] as List<dynamic>?;

      String? downloadUrl;
      if (assets != null) {
        for (final asset in assets) {
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'] as String?;
            break;
          }
        }
      }

      final hasUpdate = _compareVersions(latestVersion, currentVersion) > 0;

      return UpdateInfo(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: body,
      );
    } catch (e) {
      final pkg = await PackageInfo.fromPlatform();
      return UpdateInfo(
        hasUpdate: false,
        currentVersion: pkg.version,
        latestVersion: pkg.version,
        error: '网络错误，请检查网络连接或挂载代理后重试',
      );
    }
  }

  int _compareVersions(String a, String b) {
    final partsA = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final partsB = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < partsA.length && i < partsB.length; i++) {
      if (partsA[i] != partsB[i]) return partsA[i] - partsB[i];
    }
    return partsA.length - partsB.length;
  }
}
