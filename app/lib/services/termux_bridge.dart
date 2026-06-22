import 'package:flutter/services.dart';

class TermuxBridge {
  static const _channel = MethodChannel('com.opencode.mobile/native');

  static const _termuxPackage = 'com.termux';
  static const _prootDistroBin =
      '/data/data/com.termux/files/usr/bin/proot-distro';

  Future<String> getArch() async {
    try {
      return await _channel.invokeMethod<String>('getArch') ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isTermuxInstalled() async {
    try {
      return await _channel.invokeMethod<bool>('isAppInstalled', {
        'packageName': _termuxPackage,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isProotDistroInstalled() async {
    try {
      return await _channel.invokeMethod<bool>('checkFileExists', {
        'path': _prootDistroBin,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isUbuntuInstalled() async {
    try {
      return await _channel.invokeMethod<bool>('checkFileExists', {
        'path':
            '/data/data/com.termux/files/usr/var/lib/proot-distro/installed-distros/ubuntu/etc/os-release',
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> installProotDistro() async {
    try {
      return await _channel.invokeMethod<bool>('runTermuxCommand', {
        'command': 'pkg install -y proot-distro 2>&1',
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> installUbuntu() async {
    try {
      return await _channel.invokeMethod<bool>('runTermuxCommand', {
        'command': 'proot-distro install ubuntu 2>&1',
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setupProotEnvironment() async {
    try {
      return await _channel.invokeMethod<bool>('runTermuxCommand', {
        'command':
            'proot-distro login ubuntu -- bash -c "apt update && apt install -y nodejs npm && npm install -g opencode-ai" 2>&1',
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startProotServe() async {
    try {
      return await _channel.invokeMethod<bool>('runTermuxCommand', {
        'command':
            'proot-distro login ubuntu -- bash -c "nohup opencode serve --port 4096 --hostname 0.0.0.0 --cors \\"*\\" > \$HOME/opencode.log 2>&1 &" 2>&1',
      }) ?? false;
    } catch (_) {
      return false;
    }
  }
}
