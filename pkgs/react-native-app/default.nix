{ pkgs, lib, ... }:
let
  androidSdk = pkgs.androidenv.androidPkgs_9_0.androidsdk;
in
pkgs.mkShell {
  name = "react-native-dev";

  nativeBuildInputs = with pkgs; [
    # Core JS/React tools
    nodejs_20
    yarn
    watchman

    # React Native CLI
    (pkgs.writeShellScriptBin "react-native" ''
      exec ${pkgs.nodejs_20}/bin/npx react-native "$@"
    '')

    # Development tools
    cocoapods
    jdk17
    gradle
  ] ++ lib.optionals pkgs.stdenv.isDarwin (with pkgs.darwin.apple_sdk.frameworks; [
    # iOS specific
    CoreServices
    Foundation
    UIKit
    Security
    xcbuild
    xcodebuild
  ]);

  buildInputs = with pkgs; [
    androidSdk
  ];

  ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
  ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
  JAVA_HOME = pkgs.jdk17.home;

  shellHook = ''
    export PATH="$PATH:${pkgs.nodejs_20}/bin"
    export PATH="$PATH:${androidSdk}/libexec/android-sdk/platform-tools"

    echo "🚀 React Native Development Environment"
    echo "======================================="

    ${pkgs.gum}/bin/gum style --border normal --margin "1" --padding "1" "Available commands:
    • react-native init MyApp  - Create new project
    • cd MyApp && yarn start   - Start Metro bundler
    • react-native run-ios     - Run iOS simulator
    • react-native run-android - Run Android emulator"

    if [ ! -d "node_modules" ] && [ -f "package.json" ]; then
      echo "📦 Installing dependencies..."
      yarn install
    fi

    if ${pkgs.gum}/bin/gum confirm "Initialize new React Native project?"; then
      PROJECT_NAME=$(${pkgs.gum}/bin/gum input --placeholder "Project name")
      react-native init "$PROJECT_NAME" --template react-native-template-typescript
    fi
  '';

    # Environment variables for iOS development on Darwin
    #shellHook = lib.optionalString pkgs.stdenv.isDarwin ''
    #  export DEVELOPER_DIR="${pkgs.xcode}/Applications/Xcode.app/Contents/Developer"
    #  export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
    #'';
}

