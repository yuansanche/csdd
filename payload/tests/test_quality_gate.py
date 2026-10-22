"""Behavior tests: absent/invalid evidence, failed or timed out checks must block."""
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts/quality_gate.py"


class QualityGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "project"
        self.root.mkdir()
        files = ["README.md", "AGENTS.md", ".specify/memory/constitution.md", "docs/standards/coding-standards.md", "docs/standards/external-standards.md", "docs/architecture.md", "docs/workflow.md", "docs/quality-gates.md", "docs/testing.md", "docs/release.md", "CONTRIBUTING.md"]
        for name in files:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("# Synthetic fixture\n", encoding="utf-8")
        (self.root / ".specify/memory/constitution.md").write_text("**Version**: 1.0.0\n")
        for name in ["spec-template.md", "plan-template.md", "tasks-template.md"]:
            path = self.root / ".specify/templates/overrides" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("Project Governance v1.0.0\n")
        (self.root / "quality-policy.json").write_text(json.dumps({"schema_version": 1, "rule_version": "1.0.0", "required_files": files, "required_categories": ["build", "test", "format", "architecture", "security"], "active_feature": None, "checks": []}))
        (self.root / "sources.lock.json").write_text(json.dumps({"rule_version": "1.0.0", "specify_cli_version": "1.1.3"}))
        (self.root / ".specify/integration.json").write_text(json.dumps({"version": "1.1.3"}))

    def tearDown(self):
        self.temp.cleanup()

    def run_gate(self, mode="bootstrap"):
        return subprocess.run([sys.executable, str(RUNNER), "--root", str(self.root), "--mode", mode], capture_output=True, text=True)

    def set_policy(self, mutate):
        p = self.root / "quality-policy.json"
        d = json.loads(p.read_text())
        mutate(d)
        p.write_text(json.dumps(d))

    def make_feature(self):
        p = self.root / "specs/001-test"
        p.mkdir(parents=True)
        (p / "spec.md").write_text("# Spec\n\n- **FR-001**: Published version must stay immutable.\n")
        (p / "plan.md").write_text("# Plan\nImmutable version is owned by the rules module.\n")
        (p / "tasks.md").write_text("- [ ] T001 [FR-001] Implement immutable version.\n")
        test = self.root / "tests/application_test.py"
        test.parent.mkdir(parents=True, exist_ok=True)
        test.write_text("# This fixture only checks reference validation.\n")
        (p / "acceptance.json").write_text(json.dumps({"requirements": [{"id": "FR-001", "acceptance": ["Published content cannot change"], "tasks": ["T001"], "tests": [{"path": "tests/application_test.py", "selector": "test_immutable"}]}]}))
        checks = [{"id": category, "category": category, "argv": [sys.executable, "-c", "print('fixture check')"], "timeout_seconds": 5} for category in ["build", "test", "format", "architecture", "security"]]
        self.set_policy(lambda d: d.update(active_feature="specs/001-test", checks=checks))

    def test_fixture_does_not_inherit_users_real_check_configuration(self):
        configured = self.root / "configured-source"
        configured.mkdir()
        (configured / "quality-policy.json").write_text(json.dumps({"checks": [{"id": "real-build"}], "active_feature": "specs/real"}))
        other = QualityGateTests()
        with patch.dict(globals(), ROOT=configured):
            other.setUp()
        try:
            policy = json.loads((other.root / "quality-policy.json").read_text())
            self.assertEqual(policy["checks"], [])
            self.assertIsNone(policy["active_feature"])
        finally:
            other.tearDown()

    def test_nested_dependency_documents_do_not_block_project_links(self):
        p = self.root / "frontend/node_modules/widget/README.md"
        p.parent.mkdir(parents=True)
        p.write_text("[Package source](not-in-package.md)")
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_nested_dependency_source_does_not_trigger_product_delivery(self):
        p = self.root / "frontend/node_modules/widget/index.js"
        p.parent.mkdir(parents=True)
        p.write_text("export const value = 1;")
        result = self.run_gate("ci")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_valid_bootstrap_passes_without_claiming_product_quality(self):
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads((self.root / "reports/quality-report.json").read_text())
        self.assertFalse(report["product_checks_executed"])

    def test_missing_required_document_blocks(self):
        (self.root / "docs/architecture.md").unlink()
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("docs/architecture.md", result.stdout + result.stderr)

    def test_broken_local_link_blocks(self):
        with (self.root / "README.md").open("a") as f:
            f.write("\n[Broken](missing.md)\n")
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing.md", result.stdout + result.stderr)

    def test_malformed_policy_blocks(self):
        (self.root / "quality-policy.json").write_text("{")
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("policy", result.stdout.lower() + result.stderr.lower())

    def test_invalid_required_file_type_blocks(self):
        self.set_policy(lambda d: d.update(required_files=[42]))
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("required_files", result.stdout + result.stderr)

    def test_unconfigured_delivery_blocks(self):
        result = self.run_gate("delivery")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checks", result.stdout + result.stderr)

    def test_delivery_runs_configured_checks(self):
        self.make_feature()
        result = self.run_gate("delivery")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads((self.root / "reports/quality-report.json").read_text())
        self.assertTrue(report["product_checks_executed"])
        self.assertEqual(len(report["commands"]), 5)

    def test_failed_business_check_blocks(self):
        self.make_feature()
        self.set_policy(lambda d: d["checks"][0].update(argv=[sys.executable, "-c", "raise SystemExit(7)"]))
        result = self.run_gate("delivery")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exit 7", result.stdout + result.stderr)

    def test_timed_out_check_blocks(self):
        self.make_feature()
        self.set_policy(lambda d: d["checks"][0].update(argv=[sys.executable, "-c", "import time; time.sleep(5)"], timeout_seconds=0.05))
        result = self.run_gate("delivery")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("timeout", result.stdout + result.stderr)

    def test_test_path_escape_blocks(self):
        self.make_feature()
        p = self.root / "specs/001-test/acceptance.json"
        d = json.loads(p.read_text())
        d["requirements"][0]["tests"][0]["path"] = "../external.py"
        p.write_text(json.dumps(d))
        result = self.run_gate("delivery")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside", result.stdout + result.stderr)

    def test_missing_requirement_mapping_blocks(self):
        self.make_feature()
        p = self.root / "specs/001-test/spec.md"
        p.write_text(p.read_text() + "\n- **FR-002**: History keeps original version.\n")
        result = self.run_gate("delivery")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FR-002", result.stdout + result.stderr)

    def test_ci_with_business_source_requires_delivery_checks(self):
        p = self.root / "src/main.java"
        p.parent.mkdir()
        p.write_text("class Main {}")
        result = self.run_gate("ci")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("checks", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
