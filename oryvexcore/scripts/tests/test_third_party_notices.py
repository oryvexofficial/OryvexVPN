import importlib.util
import os
import unittest

SCRIPT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "third-party-notices.py"))
spec = importlib.util.spec_from_file_location("third_party_notices", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StandardTextsPathTest(unittest.TestCase):
    def test_resolves_root_license_texts_from_script_location(self):
        expected = os.path.abspath(os.path.join(os.path.dirname(SCRIPT), "..", "..", "license-texts"))
        actual = module.standard_texts_dir(SCRIPT)
        self.assertEqual(actual, expected)
        self.assertTrue(os.path.isdir(actual))
        self.assertTrue(os.path.isfile(os.path.join(actual, "MIT.txt")))


if __name__ == "__main__":
    unittest.main()
