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
# Keep FLUTTER_VERSION in step with the SDK used locally (flutter --version).

set -e

FLUTTER_VERSION=3.38.5
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

# Belt and braces: every plugin this app uses resolves through CocoaPods
# (the generated Swift package has no dependencies), so Pods/ has to exist
# before Xcode opens the workspace.
cd "$CLIENT_DIR/ios"
pod install
