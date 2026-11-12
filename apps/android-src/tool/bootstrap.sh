#!/usr/bin/env bash
# Fills in Flutter's Android boilerplate (gradle wrapper glue) around the committed manifest,
# Kotlin service, icons and Gradle config. `flutter create` never overwrites an existing file.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter create --org com.oryvex --project-name oryvexcore --platforms android --android-language kotlin .
git checkout -- test/widget_test.dart 2>/dev/null || true
flutter pub get
echo "android bootstrap done"
