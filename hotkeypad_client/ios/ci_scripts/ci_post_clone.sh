#!/bin/sh
# Xcode Cloud runs this right after cloning, before it resolves
# dependencies or plans the Runner scheme.
#
# A fresh clone is not buildable on its own: Flutter/Generated.xcconfig,
# Flutter/ephemeral/, Runner/GeneratedPluginRegistrant.* and Pods/ are all
# generated and all gitignored, and the clone has no Flutter SDK to
# generate them with. Without this script the build dies at "Resolve
# package dependencies" / "Failed to catalog app correctly".
#
# Keep FLUTTER_VERSION in step with the SDK used locally (flutter --version),
# and no older than what the dependencies require (flutter_zxing needs
# Flutter >= 3.41 / Dart >= 3.11).

set -e

FLUTTER_VERSION=3.47.2
CLIENT_DIR="$CI_PRIMARY_REPOSITORY_PATH/hotkeypad_client"

echo "--- Installing Flutter $FLUTTER_VERSION"
git clone --depth 1 --branch "$FLUTTER_VERSION" \
  https://github.com/flutter/flutter.git "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true
flutter --version
flutter precache --ios

echo "--- Installing CocoaPods"
HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods

# --config-only stops short of an actual build: it just regenerates the
# Xcode config, the plugin registrant and the plugin Swift package, and
# runs pod install. That is exactly the state a clone is missing.
echo "--- Generating the iOS build config"
cd "$CLIENT_DIR"
flutter pub get
flutter build ios --config-only --release --no-codesign

# Belt and braces: plugins now resolve through the generated Swift package,
# but the Runner project still includes the Pods xcconfigs, so Pods/ has to
# exist before Xcode opens the workspace.
cd "$CLIENT_DIR/ios"
pod install
