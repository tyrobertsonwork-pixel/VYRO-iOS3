#!/usr/bin/env bash
set -Eeuo pipefail

echo "🚀 Installing VYRO native MKV playback integration"
echo "=================================================="

# Run from the repository root. This script deliberately does not create a
# second Capacitor plugin or replace VYRO's existing player implementation.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

echo "🔎 Checking required project files..."
required=(
  "package.json"
  "capacitor.config.ts"
  "scripts/integrate-native-player.rb"
  "native/ios/AetherPlayerPlugin.swift"
  "native/ios/VYROBridgeViewController.swift"
  ".github/workflows/ios-unsigned-ipa.yml"
)

for file in "${required[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "❌ Required file missing: $file" >&2
    exit 1
  fi
  echo "  ✓ $file"
done

if [[ ! -d "ios/App/App.xcodeproj" || ! -f "ios/App/App.xcworkspace/contents.xcworkspacedata" ]]; then
  echo "❌ The Capacitor iOS platform has not been generated."
  echo "   Run 'npx cap add ios' and 'npx cap sync ios' before this installer."
  exit 1
fi

echo "📦 Installing the Xcode project integration dependency..."
gem install xcodeproj --no-document

echo "🔧 Integrating the existing AetherEngine player into the iOS project..."
ruby scripts/integrate-native-player.rb

echo "🔍 Verifying native integration..."
for file in \
  "ios/App/App/AetherPlayerPlugin.swift" \
  "ios/App/App/VYROBridgeViewController.swift" \
  "ios/App/App.xcodeproj/project.pbxproj" \
  "ios/App/App/Base.lproj/Main.storyboard"; do
  if [[ ! -f "$file" ]]; then
    echo "❌ Integration output missing: $file" >&2
    exit 1
  fi
  echo "  ✓ $file"
done

if ! grep -q 'VYROBridgeViewController' ios/App/App/Base.lproj/Main.storyboard; then
  echo "❌ Native Capacitor bridge controller was not registered in the storyboard." >&2
  exit 1
fi

if ! grep -q 'AetherEngine' ios/App/App.xcodeproj/project.pbxproj; then
  echo "❌ AetherEngine Swift package dependency was not added to the Xcode project." >&2
  exit 1
fi

echo ""
echo "✅ VYRO native playback integration is installed."
echo "ℹ️ This step prepares the native engine; only a successful device playback test confirms MKV playback."
