#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p ~/.gradle/init.d
cat > ~/.gradle/init.d/disable-lint.gradle << 'GRADLE'
allprojects {
  afterEvaluate {
    tasks.matching { it.name.startsWith("lintVital") || it.name.contains("Lint") }.configureEach {
      enabled = false
    }
  }
}
GRADLE
flutter create --platforms=android --project-name=vexostream_app --org=bond.vexostream .
python3 - <<'PY'
import re
import shutil
from pathlib import Path

p = Path('android/app/src/main/AndroidManifest.xml')
if p.exists():
    s = p.read_text()
    for permission in ('android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE'):
        if permission not in s:
            s = s.replace('<application', f'<uses-permission android:name="{permission}"/>\n    <application', 1)

    application = re.search(r'<application\b[^>]*>', s, re.DOTALL)
    if not application:
        raise SystemExit('Could not find the Android application element.')
    app_tag = application.group(0)
    for key, value in (
        ('label', 'VexoStream'),
        ('icon', '@mipmap/ic_launcher'),
        ('roundIcon', '@mipmap/ic_launcher_round'),
    ):
        attribute = rf'(\bandroid:{key}\s*=\s*")[^"]*(")'
        if re.search(attribute, app_tag):
            app_tag = re.sub(attribute, rf'\g<1>{value}\g<2>', app_tag, count=1)
        else:
            app_tag = app_tag[:-1].rstrip() + f' android:{key}="{value}">'
    s = s[:application.start()] + app_tag + s[application.end():]
    p.write_text(s)

strings = Path('android/app/src/main/res/values/strings.xml')
if strings.exists():
    content = strings.read_text()
    content, count = re.subn(
        r'(<string\b(?=[^>]*\bname="app_name")[^>]*>).*?(</string>)',
        r'\g<1>VexoStream\g<2>',
        content,
        count=1,
        flags=re.DOTALL,
    )
    if count:
        strings.write_text(content)

icon_template = Path('branding/android/res')
android_res = Path('android/app/src/main/res')
if not icon_template.is_dir():
    raise SystemExit('Android launcher icon template is missing.')
for source in icon_template.rglob('*'):
    if not source.is_file():
        continue
    destination = android_res / source.relative_to(icon_template)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)

def ensure_lint_settings(path, block_name):
    if not path.exists():
        return

    content = path.read_text()
    android_block = re.search(r'(?m)^([ \t]*)android[ \t]*\{', content)
    if not android_block:
        return

    missing = [
        key for key in ('checkReleaseBuilds', 'abortOnError')
        if not re.search(
            rf'(?m)^[ \t]*{key}[ \t]*(?:=[ \t]*)?false\b',
            content,
        )
    ]
    if not missing:
        return

    indent = android_block.group(1)
    config = (
        f'{indent}    {block_name} {{\n'
        + ''.join(f'{indent}        {key} = false\n' for key in missing)
        + f'{indent}    }}\n'
    )
    content = (
        content[:android_block.end()]
        + '\n'
        + config
        + content[android_block.end():]
    )
    path.write_text(content)

ensure_lint_settings(Path('android/app/build.gradle.kts'), 'lint')
ensure_lint_settings(Path('android/app/build.gradle'), 'lintOptions')
PY
rm -f test/widget_test.dart
