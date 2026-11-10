#!/usr/bin/env bash
# Fills in Flutter's Windows boilerplate around the committed runner. `flutter create` never
# overwrites an existing file, so main.cpp, Runner.rc and the icon stay as committed.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter create --org com.oryvex --project-name oryvexcore --platforms windows .
if [ -f windows/CMakeLists.txt ]; then
  sed -i.bak 's/set(BINARY_NAME "oryvexcore")/set(BINARY_NAME "OryvexVPN")/' windows/CMakeLists.txt && rm -f windows/CMakeLists.txt.bak
fi
# The window is shown by window_manager in lib/main.dart, so "--background" can keep it hidden.
if [ -f windows/runner/flutter_window.cpp ]; then
  sed -i.bak 's|^[[:space:]]*this->Show();|    // Shown by window_manager in lib/main.dart.|' windows/runner/flutter_window.cpp && rm -f windows/runner/flutter_window.cpp.bak
fi
git checkout -- test/widget_test.dart 2>/dev/null || true
flutter pub get
echo "desktop bootstrap done"
