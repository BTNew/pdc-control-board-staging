"""
Assemble a clean, staging-free production deployment artifact from the
working repo, and validate it. Never deploys anything -- writes the
artifact to a local directory and runs safety scans against it.

Excludes (per the production-readiness brief):
  staging.html, pdc-supabase-config.staging.js, data-staging-empty.js,
  pdc-auth-registration.js (staging-only self-registration module),
  _staging_test_tools/, any *.staging.* file, synthetic fixtures, test
  account credentials, backup data, .env files, and anything containing
  the staging Supabase project ref.

Includes exactly the files production's own index.html references (the
existing production entry point), so the artifact matches what is
already live today plus only the reviewed source changes in this repo --
nothing staging-only leaks in by construction, and the scan below fails
loudly if it ever does.
"""
import hashlib
import re
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ARTIFACT_DIR = REPO_ROOT / "_build" / "production-artifact"

STAGING_PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_PROJECT_REF = "vjdtsswhroyguxyfjdkt"
PRODUCTION_DOMAIN = "pdccontrolboard.com"

# Exact file list mirrors production's existing index.html script/asset
# references (fetched from the live production repo/site during the
# read-only assessment) -- NOT staging.html's list, which additionally
# includes the staging-only auth-registration module.
PRODUCTION_FILES = [
    "index.html",
    "app.js",
    "pdc-auth.js",
    "pdc-supabase-config.js",
    "data.js",
    "email-board-data.js",
    "arb-labor-catalog.js",
    "styles.css",
    "desktop-operations.css",
    "workshop-planner.css",
    "workshop-planner.js",
    "workshop-data-service.js",
    "workshop-realtime.js",
    "workshop-shared-actions.js",
    "vehicle-lifecycle-actions.js",
    "vendor/supabase/supabase-2.110.5.js",
    "assets/pmb-logo.png",
    "favicon.svg",
]

# Files that must exist in the artifact but are not present in this
# working repo's checkout (they were added directly in prior deploy
# folders / live only in the production repo). Written verbatim below
# rather than copied, since there is nothing to copy from.
SYNTHESIZED_FILES = {
    "robots.txt": "User-agent: *\nDisallow: /\n",
    ".nojekyll": "",
}

# random-100-vehicles.csv currently exists in the LIVE production repo
# but is explicitly excluded here as synthetic/test data per the
# production-readiness brief ("Exclude ... Synthetic fixtures"). Its
# removal from production is a cutover-plan action item, not something
# this clean artifact re-ships.

# Never allowed in the artifact regardless of the above list (defence in
# depth -- if any of these ever get added to PRODUCTION_FILES by
# mistake, the build step below refuses to copy them).
FORBIDDEN_FILENAMES = {
    "staging.html",
    "pdc-supabase-config.staging.js",
    "data-staging-empty.js",
    "pdc-auth-registration.js",
    ".env",
    ".env.local",
    ".env.staging",
    ".env.production",
}
FORBIDDEN_PATH_FRAGMENTS = ("_staging_test_tools", "backups", ".staging.")


def build_artifact():
    if ARTIFACT_DIR.exists():
        shutil.rmtree(ARTIFACT_DIR)
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)

    copied = []
    missing = []
    for rel_path in PRODUCTION_FILES:
        filename = Path(rel_path).name
        if filename in FORBIDDEN_FILENAMES or any(frag in rel_path for frag in FORBIDDEN_PATH_FRAGMENTS):
            raise RuntimeError(f"refusing to include forbidden path in production artifact: {rel_path}")
        source = REPO_ROOT / rel_path
        if not source.exists():
            missing.append(rel_path)
            continue
        dest = ARTIFACT_DIR / rel_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)
        copied.append(rel_path)

    for rel_path, content in SYNTHESIZED_FILES.items():
        dest = ARTIFACT_DIR / rel_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8")
        copied.append(rel_path)

    return copied, missing


SECRET_PATTERNS = [
    (re.compile(r"sb_secret_[A-Za-z0-9_\-]+"), "Supabase secret/service-role key"),
    (re.compile(r"['\"]?service_role['\"]?\s*[:=]"), "a 'service_role' key/value assignment (not just a comment mentioning it)"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "PEM private key"),
    (re.compile(r"AWS_SECRET_ACCESS_KEY|aws_secret_access_key"), "AWS secret key reference"),
    (re.compile(r"SMTP_PASSWORD|smtp_password"), "SMTP password reference"),
]


def scan_artifact():
    findings = []
    for path in ARTIFACT_DIR.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(ARTIFACT_DIR)
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue  # binary asset (e.g. the logo PNG) -- not scanned as text

        if STAGING_PROJECT_REF in text:
            findings.append(f"{rel}: contains staging Supabase project ref {STAGING_PROJECT_REF}")
        for pattern, label in SECRET_PATTERNS:
            if pattern.search(text):
                findings.append(f"{rel}: matched pattern for {label}")
        if "localhost" in text.lower() and rel.name not in ("robots.txt",):
            # Not necessarily fatal (some fallback dev-mode code paths
            # legitimately mention localhost), but flagged for manual
            # review rather than silently ignored.
            findings.append(f"{rel}: contains the literal string 'localhost' (review before shipping)")

    return findings


def confirm_production_ref_present():
    hits = []
    for path in ARTIFACT_DIR.rglob("*"):
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        if PRODUCTION_PROJECT_REF in text:
            hits.append(str(path.relative_to(ARTIFACT_DIR)))
    return hits


def confirm_domain_preserved():
    # NOTE: the read-only production assessment found GitHub Pages
    # `cname` is currently null for the production repo -- there is NO
    # custom domain configured today despite the brief's assumption that
    # pdccontrolboard.com already exists. This check therefore confirms
    # the artifact does not accidentally point at a *different* domain
    # (e.g. a staging URL) rather than asserting a domain string that
    # does not currently exist anywhere in the live deployment.
    hits = []
    for path in ARTIFACT_DIR.rglob("*.html"):
        text = path.read_text(encoding="utf-8", errors="ignore")
        if "pdc-control-board-staging" in text or "github.io/pdc-control-board-staging" in text:
            hits.append((str(path.relative_to(ARTIFACT_DIR)), "references the STAGING Pages URL"))
    return hits


def sha256_manifest():
    manifest = {}
    for path in sorted(ARTIFACT_DIR.rglob("*")):
        if path.is_file():
            manifest[str(path.relative_to(ARTIFACT_DIR))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return manifest


def main():
    copied, missing = build_artifact()
    print(f"Copied {len(copied)} files into {ARTIFACT_DIR}")
    if missing:
        print(f"WARNING: {len(missing)} expected production files were not found in the repo: {missing}")

    findings = scan_artifact()
    staging_ref_findings = [f for f in findings if STAGING_PROJECT_REF in f]

    print("\n--- Secret / staging-reference scan ---")
    if findings:
        for f in findings:
            print(" -", f)
    else:
        print(" (no findings)")

    print("\n--- Production reference presence check ---")
    prod_hits = confirm_production_ref_present()
    print(f" Files referencing production project ref {PRODUCTION_PROJECT_REF}: {prod_hits}")

    print("\n--- Domain/Pages-URL leakage check ---")
    domain_hits = confirm_domain_preserved()
    if domain_hits:
        print(f" FAIL: found staging Pages URL references: {domain_hits}")
    else:
        print(" OK: no staging Pages URL found in any HTML file. NOTE: production currently has")
        print(" no custom domain configured (GitHub Pages cname=null) -- see the read-only")
        print(" production assessment; pdccontrolboard.com does not yet exist as a live domain.")

    manifest = sha256_manifest()
    manifest_path = ARTIFACT_DIR.parent / "production-artifact-manifest.sha256.txt"
    manifest_path.write_text(
        "\n".join(f"{h}  {p}" for p, h in sorted(manifest.items())) + "\n", encoding="utf-8"
    )
    print(f"\nWrote manifest: {manifest_path} ({len(manifest)} files)")

    if staging_ref_findings:
        print("\nFAIL: staging Supabase reference found in production artifact.")
        sys.exit(1)
    if not prod_hits:
        print("\nFAIL: production Supabase reference not found anywhere in the artifact.")
        sys.exit(1)
    if domain_hits:
        print("\nFAIL: staging Pages URL leaked into the production artifact.")
        sys.exit(1)

    print("\nPASS: production artifact validation succeeded. NOT DEPLOYED -- local build only.")


if __name__ == "__main__":
    main()
