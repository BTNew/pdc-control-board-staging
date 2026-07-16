"""Build the sanitised, authenticated PDC static login site."""

from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "backend" / ".generated" / "pdc-control-board-login"
FILES = (
    "index.html",
    "favicon.svg",
    "styles.css",
    "desktop-operations.css",
    "workshop-planner.css",
    "random-100-vehicles.csv",
    "assets/pmb-logo.png",
    "vendor/supabase/supabase-2.110.5.js",
    "vendor/qz/qz-tray.js",
    "vendor/pdfjs/pdf.min.js",
    "vendor/pdfjs/pdf.worker.min.js",
    "pdc-supabase-config.js",
    "pdc-auth.js",
    "data.js",
    "email-board-data.js",
    "arb-labor-catalog.js",
    "workshop-data-service.js",
    "workshop-planner.js",
    "app.js",
)


def main() -> None:
    config = (ROOT / "pdc-supabase-config.js").read_text(encoding="utf-8")
    executable_config = "\n".join(line for line in config.splitlines() if not line.lstrip().startswith("//"))
    forbidden = ("service_role", "service-role", "client_secret", "password=")
    found = [item for item in forbidden if item in executable_config.lower()]
    if found:
        raise SystemExit(f"Refusing browser bundle: forbidden configuration markers: {', '.join(found)}")

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

    # Comments document local secret-handling rules but are unnecessary in the public browser config.
    (TARGET / "pdc-supabase-config.js").write_text(executable_config.strip() + "\n", encoding="utf-8", newline="\n")

    (TARGET / "robots.txt").write_text("User-agent: *\nDisallow: /\n", encoding="utf-8", newline="\n")
    (TARGET / ".nojekyll").write_text("", encoding="utf-8")

    for name in ("data.js", "email-board-data.js"):
        payload = (TARGET / name).read_text(encoding="utf-8").replace(" ", "")
        if '"vehicles":[]' not in payload and "vehicles:[]" not in payload:
            raise SystemExit(f"Refusing browser bundle: {name} is not a zero-vehicle payload")

    total = sum(path.stat().st_size for path in TARGET.rglob("*") if path.is_file() and ".git" not in path.parts)
    print(f"Built {len(FILES) + 2} sanitised browser assets ({total} bytes) at {TARGET}")


if __name__ == "__main__":
    main()
