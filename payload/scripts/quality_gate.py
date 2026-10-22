"""Validate governance artifacts and run explicitly configured delivery checks.

Python 3.10+, standard library only. This does not prove business correctness.
"""
import argparse
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote, urlsplit


class GateError(Exception):
    """An unmet gate; exit nonzero and preserve the reason in the report."""


CORE_FILES = [
    "README.md", "AGENTS.md", ".specify/memory/constitution.md",
    "docs/standards/coding-standards.md", "docs/standards/external-standards.md",
    "docs/architecture.md", "docs/workflow.md", "docs/quality-gates.md",
    "docs/testing.md", "docs/release.md", "CONTRIBUTING.md",
]
CATEGORIES = {"build", "test", "format", "architecture", "security"}
OVERRIDES = ["spec-template.md", "plan-template.md", "tasks-template.md"]
IGNORED_DIRS = {".git", "node_modules", ".venv", "venv", "target", "build", "dist", "coverage", "__pycache__", "reports", ".pytest_cache", ".mypy_cache"}


def project_files(root):
    """Prune dependency/generated directories at any depth, including monorepos."""
    for directory, dirs, filenames in os.walk(root):
        dirs[:] = [name for name in dirs if name not in IGNORED_DIRS]
        for name in filenames:
            path = Path(directory) / name
            if path.is_file():
                yield path


def inside(root, value):
    if not isinstance(value, str) or not value.strip():
        raise GateError("path must be a non-empty string")
    path = (root / value).resolve()
    if not path.is_relative_to(root):
        raise GateError(f"path outside project: {value}")
    return path


def strings(value, label, allow_empty=False):
    if not isinstance(value, list) or (not value and not allow_empty):
        raise GateError(f"{label} must be a {'possibly empty ' if allow_empty else 'non-empty '}list")
    if any(not isinstance(item, str) or not item.strip() for item in value):
        raise GateError(f"{label} must contain non-empty strings")
    return value


def object_json(path, label):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise GateError(f"{label}: {exc}") from exc
    if not isinstance(data, dict):
        raise GateError(f"{label} must be an object")
    return data


def governance(root):
    policy = object_json(root / "quality-policy.json", "policy")
    if policy.get("schema_version") != 1:
        raise GateError("policy schema_version must be 1")
    version = policy.get("rule_version")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise GateError("policy rule_version must be a semantic version")
    required = strings(policy.get("required_files"), "required_files")
    for name in dict.fromkeys(CORE_FILES + required):
        if not inside(root, name).is_file():
            raise GateError(f"required file missing: {name}")
    constitution = (root / ".specify/memory/constitution.md").read_text(encoding="utf-8")
    if f"**Version**: {version}" not in constitution:
        raise GateError("policy and constitution rule_version differ")
    for name in OVERRIDES:
        path = root / ".specify/templates/overrides" / name
        if not path.is_file() or f"Project Governance v{version}" not in path.read_text(encoding="utf-8"):
            raise GateError(f"project template override missing or version mismatch: {name}")
    lock = object_json(root / "sources.lock.json", "source baseline")
    integration = object_json(root / ".specify/integration.json", "Spec Kit integration")
    if lock.get("rule_version") != version or integration.get("version") != lock.get("specify_cli_version"):
        raise GateError("source / rule / initialization versions differ")
    for path in project_files(root):
        if path.suffix != ".md":
            continue
        relative = path.relative_to(root).as_posix()
        if relative.startswith((".git/", ".agents/", "reports/")):
            continue
        if relative.startswith(".specify/") and not relative.startswith((".specify/memory/", ".specify/templates/overrides/")):
            continue
        text = re.sub(r"```.*?```", "", path.read_text(encoding="utf-8"), flags=re.S)
        for target in re.findall(r"\[[^\]\n]*\]\(([^)\n]+)\)", text):
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            destination = (path.parent / unquote(parsed.path)).resolve()
            if not destination.is_relative_to(root) or not destination.exists():
                raise GateError(f"broken local link: {relative} -> {target}")
    return policy


def business_sources(root):
    suffixes = {".java", ".kt", ".py", ".js", ".jsx", ".ts", ".tsx", ".sql", ".sh"}
    own_files = {"scripts/quality_gate.py", "tests/test_quality_gate.py"}
    result = []
    for path in project_files(root):
        relative = path.relative_to(root).as_posix()
        if relative.startswith((".git/", ".specify/", ".agents/", "examples/", "reports/", "node_modules/", ".venv/")):
            continue
        if "__pycache__" in path.parts or relative in own_files:
            continue
        if path.is_file() and path.suffix in suffixes:
            result.append(relative)
    return sorted(result)


def delivery_configuration(root, policy, feature_argument):
    checks = policy.get("checks")
    if not isinstance(checks, list) or not checks:
        raise GateError("delivery checks are not configured; governance success is not product acceptance")
    required = set(strings(policy.get("required_categories"), "required_categories"))
    if not CATEGORIES.issubset(required):
        raise GateError("required_categories cannot silently remove baseline categories")
    seen = set()
    for check in checks:
        if not isinstance(check, dict):
            raise GateError("checks items must be objects")
        identifier = check.get("id")
        if not isinstance(identifier, str) or not identifier.strip() or identifier in seen:
            raise GateError("checks ids must be non-empty and unique")
        seen.add(identifier)
        strings(check.get("argv"), f"checks[{identifier}].argv")
        category = check.get("category")
        if not isinstance(category, str) or category not in required:
            raise GateError(f"checks[{identifier}] has unknown category")
        timeout = check.get("timeout_seconds", 600)
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not 0 < timeout <= 3600:
            raise GateError(f"checks[{identifier}] timeout_seconds must be within (0, 3600]")
    missing = required - {check["category"] for check in checks}
    if missing:
        raise GateError(f"checks missing categories: {', '.join(sorted(missing))}")
    feature = inside(root, feature_argument or policy.get("active_feature"))
    specs = root / "specs"
    if not feature.is_relative_to(specs) or not feature.is_dir():
        raise GateError("delivery feature must be a real directory under specs/")
    for name in ["spec.md", "plan.md", "tasks.md", "acceptance.json"]:
        if not (feature / name).is_file():
            raise GateError(f"feature file missing: {name}")
    spec = (feature / "spec.md").read_text(encoding="utf-8")
    if re.search(r"\[NEEDS CLARIFICATION|\bTODO\b|\bTBD\b", spec):
        raise GateError("feature spec contains unresolved placeholders")
    identifiers = set(re.findall(r"\bFR-\d{3,}\b", spec))
    if not identifiers:
        raise GateError("feature spec has no FR requirement ids")
    tasks = set(re.findall(r"(?m)^- \[[ xX]\] (T\d{3,})\b", (feature / "tasks.md").read_text(encoding="utf-8")))
    acceptance = object_json(feature / "acceptance.json", "acceptance")
    requirements = acceptance.get("requirements")
    if not isinstance(requirements, list) or not requirements:
        raise GateError("acceptance requirements must be non-empty")
    mapped = set()
    for item in requirements:
        if not isinstance(item, dict):
            raise GateError("acceptance requirement must be an object")
        identifier = item.get("id")
        if not isinstance(identifier, str) or identifier not in identifiers or identifier in mapped:
            raise GateError(f"unknown or duplicated requirement: {identifier}")
        mapped.add(identifier)
        strings(item.get("acceptance"), f"{identifier}.acceptance")
        references = strings(item.get("tasks"), f"{identifier}.tasks")
        if not set(references).issubset(tasks):
            raise GateError(f"{identifier} refers to missing task")
        tests = item.get("tests")
        if not isinstance(tests, list) or not tests:
            raise GateError(f"{identifier} has no tests")
        for test in tests:
            if not isinstance(test, dict) or not isinstance(test.get("selector"), str) or not test["selector"].strip():
                raise GateError(f"{identifier} test selector missing")
            if not inside(root, test.get("path")).is_file():
                raise GateError(f"{identifier} test file missing: {test.get('path')}")
    if identifiers != mapped:
        raise GateError(f"requirements missing mapping: {', '.join(sorted(identifiers - mapped))}")
    return checks, feature.relative_to(root).as_posix()


def execute_checks(root, checks, report):
    report["product_checks_executed"] = True
    for check in checks:
        entry = {"id": check["id"], "category": check["category"], "argv": check["argv"]}
        report["commands"].append(entry)
        try:
            result = subprocess.run(check["argv"], cwd=root, capture_output=True, text=True, timeout=check.get("timeout_seconds", 600), shell=False)
        except subprocess.TimeoutExpired as exc:
            entry["status"] = "timeout"
            raise GateError(f"check {check['id']}: timeout") from exc
        except OSError as exc:
            entry["status"] = "could-not-run"
            raise GateError(f"check {check['id']}: could not run: {exc}") from exc
        entry.update(exit_code=result.returncode, status="passed" if result.returncode == 0 else "failed")
        log = root / "reports" / f"check-{len(report['commands']):03}.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(result.stdout + result.stderr, encoding="utf-8")
        entry["log"] = log.relative_to(root).as_posix()
        if result.returncode != 0:
            raise GateError(f"check {check['id']}: exit {result.returncode}; see {entry['log']}")


def revision(root):
    try:
        top = subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True)
        if Path(top.stdout.strip()).resolve() != root:
            return None
        return subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--mode", choices=["bootstrap", "delivery", "ci"], default="bootstrap")
    parser.add_argument("--feature")
    args = parser.parse_args()
    root = args.root.resolve()
    report = {"time_utc": datetime.now(timezone.utc).isoformat(), "mode": args.mode,
              "git_revision": revision(root), "product_checks_executed": False, "commands": [],
              "scope": "governance structure and local file links; no business correctness claim"}
    try:
        policy = governance(root)
        sources = business_sources(root) if args.mode == "ci" else []
        report["business_source_files"] = sources
        if args.mode == "delivery" or (args.mode == "ci" and sources):
            checks, feature = delivery_configuration(root, policy, args.feature)
            report["feature"] = feature
            report["scope"] = "governance, requirement reference structure and configured command exit statuses"
            execute_checks(root, checks, report)
        report["status"] = "passed"
    except (GateError, OSError, ValueError) as exc:
        report.update(status="failed", error=str(exc))
    destination = root / "reports/quality-report.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{report['status'].upper()}: {report.get('error', report['scope'])}")
    print("Report: reports/quality-report.json")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
