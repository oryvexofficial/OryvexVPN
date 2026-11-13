from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

def text(name):
    return (ROOT / name).read_text(encoding='utf-8')

class FoxNativeChecks(unittest.TestCase):
    def test_old_panel_assets_removed(self):
        web = ROOT / 'fox/core/internal/service/web'
        for name in ('index.html', 'app.js', 'app.css', 'icon.png'):
            self.assertFalse((web / name).exists(), name)
        handler = text('fox/core/internal/service/dashboard.go')
        self.assertNotIn('http.FileServerFS', handler)
        self.assertNotIn('mux.HandleFunc("POST /api/session/link"', handler)
        self.assertIn('s.d.nativeOnly.Load()', handler)
        self.assertIn('local token required', handler)

    def test_both_platforms_enable_native_only_mode(self):
        for path in ('fox/core/mobile/mobile.go', 'fox/core/internal/desktop/app.go'):
            self.assertIn('d.RequireNativeClient()', text(path))

    def test_webview_handoff_and_origin_restrictions(self):
        ui = text('apps/shared/lib/src/ui/widgets/fox_web_signin.dart')
        controls = text('apps/shared/lib/src/ui/widgets/fox_controls.dart')
        self.assertIn('FoxWebSignIn(backend: widget.backend)', controls)
        self.assertIn('/api/signin/browser', ui)
        self.assertIn('call.isMainFrame', ui)
        self.assertIn("origin.host != 'accounts.firefox.com'", ui)
        self.assertIn('javaScriptBridgeForMainFrameOnly: true', ui)
        self.assertIn('javaScriptHandlersOriginAllowList', ui)
        self.assertIn('flutter_inappwebview: 6.2.0-beta.3', text('apps/shared/pubspec.yaml'))

    def test_route_card_and_backends_are_wired(self):
        home = text('apps/shared/lib/src/ui/home_page.dart')
        controls = text('apps/shared/lib/src/ui/widgets/fox_controls.dart')
        self.assertIn('FoxControls(backend: c.backend)', home)
        for endpoint in ('/api/accounts', '/api/signin', '/api/locations', '/api/location'):
            self.assertIn(endpoint, controls)
        for backend in ('desktop_backend.dart', 'android_backend.dart'):
            self.assertIn('foxRequest(', text('apps/shared/lib/src/core/' + backend))
        self.assertNotIn('openFoxDashboard', text('apps/shared/lib/src/core/backend.dart'))
        self.assertNotIn('openFoxDashboard', text('apps/android-src/android/app/src/main/kotlin/com/oryvex/oryvexcore/MainActivity.kt'))

if __name__ == '__main__':
    unittest.main()
