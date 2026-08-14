"""Build the sanitised, authenticated PDC static login site."""

from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "backend" / ".generated" / "pdc-control-board-login"
FILES = (
    "index.html",
    "staticwebapp.config.json",
    "favicon.svg",
    "styles.css",
    "desktop-operations.css",
    "workshop-planner.css",

    "assets/pmb-logo.png",
    "vendor/supabase/supabase-2.110.5.js",
    "vendor/qz/qz-tray.js",
    "vendor/pdfjs/pdf.min.js",
    "vendor/pdfjs/pdf.worker.min.js",
    "pdc-supabase-config.production.js",
    "pdc-auth.js",
    "data.js",
    "email-board-data.js",
    "arb-labor-catalog.js",
    "workshop-planner.js",
    "workshop-reference-data-service.js",
    "ai-board-advisor.js",
    "workshop-eligibility.js",
    "workshop-navigation.js",
    "vehicle-location-lifecycle.js",
    "vehicle-lifecycle-actions.js",
    "workshop-data-service.js",
    "workshop-realtime.js",
    "workshop-shared-actions.js",
    "app.js",
)


def runtime_closure_problems(target: Path = TARGET) -> list[str]:
    problems: list[str] = []
    index_text = (target / "index.html").read_text(encoding="utf-8")
    for match in re.finditer(r'(?:src|href)="([^"?]+)(?:\?[^\"]*)?"', index_text):
        reference = match.group(1)
        if reference.startswith(("http://", "https://", "#", "data:")):
            continue
        if not (target / reference).is_file():
            problems.append(f"index.html references missing asset '{reference}'")

    app_text = (target / "app.js").read_text(encoding="utf-8")
    for match in re.finditer(r"[`'\"]([A-Za-z0-9_./-]+\.js)(?:\?[^`'\"]*)?[`'\"]", app_text):
        reference = match.group(1)
        if not (target / reference).is_file():
            problems.append(f"app.js lazy-loads missing asset '{reference}'")
    return sorted(set(problems))


def main() -> None:
    config_path = ROOT / "pdc-supabase-config.production.js"
    validator = ROOT / "scripts" / "validate_public_browser_config.py"
    validation = subprocess.run(
        [sys.executable, "-I", str(validator), str(config_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if validation.returncode != 0:
        detail = validation.stderr.strip() or validation.stdout.strip() or "unknown validation failure"
        raise SystemExit(f"Refusing browser bundle: {detail}")

    if TARGET.exists():
        for child in TARGET.iterdir():
            if child.name == ".git":
                continue
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink()
    for relative in FILES:
        source = ROOT / relative
        if not source.is_file():
            raise SystemExit(f"Required browser asset is missing: {relative}")
        destination = TARGET / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


    (TARGET / "robots.txt").write_text("User-agent: *\nDisallow: /\n", encoding="utf-8", newline="\n")
    (TARGET / ".nojekyll").write_text("", encoding="utf-8")

    for name in ("data.js", "email-board-data.js"):
        payload = (TARGET / name).read_text(encoding="utf-8").replace(" ", "")
        if '"vehicles":[]' not in payload and "vehicles:[]" not in payload:
            raise SystemExit(f"Refusing browser bundle: {name} is not a zero-vehicle payload")

    closure_problems = runtime_closure_problems(TARGET)
    if closure_problems:
        raise SystemExit(f"Refusing browser bundle: {'; '.join(closure_problems)}")

    total = sum(path.stat().st_size for path in TARGET.rglob("*") if path.is_file() and ".git" not in path.parts)
    print(f"Built {len(FILES) + 2} sanitised browser assets ({total} bytes) at {TARGET}")


if __name__ == "__main__":
    main()
