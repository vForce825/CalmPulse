import pathlib, plistlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class ReleaseConfigurationTests(unittest.TestCase):
    def test_entitlements_are_minimal_and_match(self):
        for target in ['iOS','Watch','iOSWidgets','WatchWidgets']:
            with (ROOT/'Apps'/target/'CalmPulse.entitlements').open('rb') as f:
                e = plistlib.load(f)
            self.assertEqual(e['com.apple.security.application-groups'], ['group.com.vforce825.calmpulse'])
            expected={'com.apple.security.application-groups'}
            if target in ['iOS','Watch']:
                expected|={'com.apple.developer.healthkit','com.apple.developer.healthkit.background-delivery'}
                self.assertTrue(e['com.apple.developer.healthkit'])
            self.assertEqual(set(e), expected)
    def test_no_health_writes_or_server_sdk(self):
        source='\n'.join(p.read_text() for p in (ROOT/'Apps').rglob('*.swift'))
        self.assertIn('requestAuthorization(toShare: [], read: read)', source)
        for forbidden in ['import CloudKit','import Firebase','import StoreKit','URLSession.shared','startWorkoutSession','startActivity(with:']:
            self.assertNotIn(forbidden,source)
        self.assertNotIn('NSHealthUpdateUsageDescription',(ROOT/'project.yml').read_text())
    def test_ci_has_no_secrets_publishing_or_paid_compute(self):
        workflow=(ROOT/'.github/workflows/ci.yml').read_text()
        self.assertNotRegex(workflow, r'secrets\.|contents: write|macos.*large|upload-artifact|actions/cache')
        self.assertIn('runs-on: xcode-27',workflow)
        self.assertIn('timeout-minutes: 30',workflow)
        self.assertIn('persist-credentials: false',workflow)
    def test_synthetic_ui_flows_cannot_read_healthkit(self):
        runtime=(ROOT/'Apps/UI/AppRuntime.swift').read_text()
        self.assertIn('DemonstrationEmptyRepository()',runtime)
        self.assertIn('CALMPULSE_UI_TESTING',runtime)
        self.assertIn('CALMPULSE_UI_TEST_NAMESPACE',runtime)
        self.assertIn('UUID(uuidString:',runtime)
if __name__=='__main__': unittest.main()
