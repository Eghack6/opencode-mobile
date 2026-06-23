#!/bin/bash
# setup_ios.sh — 在现有 Android 项目上添加 iOS 支持
# 用法: bash setup_ios.sh <项目目录>
# 例如: bash setup_ios.sh ~/opencode-mobile/app

set -e

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

echo "=== OpenCode Mobile iOS Setup ==="
echo "Project: $(pwd)"

# Step 1: Flutter create to generate iOS scaffolding
echo ""
echo "[1/5] Generating iOS project scaffold..."
flutter create --platforms=ios . 2>&1 | tail -5

# Step 2: Patch Info.plist
echo "[2/5] Patching Info.plist..."
cat > ios/Runner/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>OpenCode Mobile</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>opencode_mobile</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleVersion</key>
	<string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UILaunchStoryboardName</key>
	<string>LaunchScreen</string>
	<key>UIMainStoryboardFile</key>
	<string>Main</string>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>UIViewControllerBasedStatusBarAppearance</key>
	<false/>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
	<key>NSLocalNetworkUsageDescription</key>
	<string>OpenCode Mobile 需要访问本地网络以连接 opencode 服务器</string>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)com.opencode.mobile</string>
	</array>
</dict>
</plist>
EOF

# Step 3: Patch Podfile
echo "[3/5] Patching Podfile..."
cat > ios/Podfile << 'EOF'
platform :ios, '14.0'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist."
  end
  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)
flutter_ios_podfile_setup

target 'Runner' do
  use_frameworks!
  use_modular_headers!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
    end
  end
end
EOF

# Step 4: Update pubspec description
echo "[4/5] Updating pubspec.yaml..."
sed -i.bak 's/description: OpenCode mobile client for Android/description: OpenCode mobile client/' pubspec.yaml 2>/dev/null || true
rm -f pubspec.yaml.bak

# Step 5: Install dependencies
echo "[5/5] Installing dependencies..."
flutter pub get

echo ""
echo "=== Done! ==="
echo ""
echo "Next steps:"
echo "  1. Copy .github/workflows/build-ios.yml to your repo root"
echo "  2. Push to GitHub"
echo "  3. Go to Actions tab → Build iOS → Run workflow"
echo "  4. Download the .app artifact when build completes"
echo ""
echo "To build locally on macOS:"
echo "  cd ios && pod install && cd .."
echo "  flutter build ios --release --no-codesign"
