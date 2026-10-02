import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class BuildConfigurationTests(unittest.TestCase):
    def test_minimum_platforms(self):
        config=(ROOT/'project.yml').read_text() if (ROOT/'project.yml').exists() else ''
        self.assertIn('iOS: "27.0"',config)
        self.assertIn('watchOS: "27.0"',config)
    def test_ci_is_standard_unsigned_without_secrets(self):
        ci=(ROOT/'.github/workflows/ci.yml').read_text() if (ROOT/'.github/workflows/ci.yml').exists() else ''
        self.assertIn('runs-on: xcode-27',ci)
        self.assertNotIn('secrets.',ci)
        self.assertIn('contents: read',ci)
        self.assertNotIn('upload-artifact',ci)
if __name__=='__main__': unittest.main()
