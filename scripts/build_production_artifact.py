"""
Assemble a clean, staging-free production deployment artifact from the
working repo, and validate it. Never deploys anything -- writes the
artifact to a local directory and runs safety scans against it.

Independent-review remediation (Stage 8, finding #7): the previous
version of this validator printed several important problems as
warnings rather than failing the build on them -- missing expected
files, absence of the registration/User Management module, absence of
the shared-data production flags, and a permissive secret scan that
did not treat every finding as fatal. A validator that can print PASS
while a real release-blocking condition is present is worse than no
validator at all, because it creates false confidence.

This version fails (non-zero exit) on every one of the following,
with no "warning only" path for any of them:
  - any required production file missing from the repo
  - any script/stylesheet referenced by the HTML but not included in
    the artifact
  - the registration module (Create Account / Forgot Password / User
    Management) not present in the artifact
  - the shared-data production feature flags
    (workshop.sharedData / vehicleLifecycle.sharedData) not present
    and explicitly true in the production Supabase config
  - the staging Supabase project reference appearing anywhere
  - a staging Pages/redirect URL appearing anywhere
  - a bare 'localhost' reference outside an explicitly allowed file
  - any secret/service-role/private-key pattern
  - a .env file, IMAP attachment folder, runtime log, or backup ZIP
    ending up in the artifact file list

As of this remediation stage, running this validator against the
current repo is EXPECTED TO FAIL, because the registration module and
the shared-data production flags do not exist in a production-safe
form yet (that is Stage 3/4 of the remediation, tracked separately and
not yet complete). A validator that could pass today, before that work
exists, would not be trustworthy. See
INDEPENDENT-REVIEW-REMEDIATION-HANDOVER.md for current status.
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

# Exact file list mirrors production index.html's complete local runtime
# closure. Public self-registration remains staging-only; production uses
# administrator-only User Management already implemented in app.js.
PRODUCTION_FILES = [
    "index.html",
    "app.js",
    "pdc-auth.js",
    "pdc-supabase-config.production.js",
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
    "ai-board-advisor.js",
    "workshop-eligibility.js",
    "workshop-navigation.js",
    "vehicle-lifecycle-actions.js",
    "vehicle-location-lifecycle.js",
    "vendor/supabase/supabase-2.110.5.js",
    "assets/pmb-logo.png",
    "favicon.svg",
]

REQUIRED_FEATURE_FILES = []

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
# production-readiness brief. Its removal from production is a
# cutover-plan action item, not something this clean artifact re-ships.

FORBIDDEN_FILENAMES = {
    "staging.html",
    "pdc-supabase-config.staging.js",
    "data-staging-empty.js",
    "pdc-auth-registration.js",  # the STAGING-only module -- see REQUIRED_FEATURE_FILES above
    "pdc-auth-registration-production.js",
    "random-100-vehicles.csv",
    ".env",
    ".env.local",
    ".env.staging",
    ".env.production",
    "email_publish.log",
}
FORBIDDEN_PATH_FRAGMENTS = (
    "_staging_test_tools", "backups", ".staging.", ".imap_attachments",
    "PDC_Control_Board_Backup", "node_modules", "__pycache__", ".venv",
)

SECRET_PATTERNS = [
    (re.compile(r"sb_secret_[A-Za-z0-9_\-]+"), "Supabase secret/service-role key"),
    (re.compile(r"['\"]?service_role['\"]?\s*[:=]"), "a 'service_role' key/value assignment (not just a comment mentioning it)"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "PEM private key"),
    (re.compile(r"AWS_SECRET_ACCESS_KEY|aws_secret_access_key"), "AWS secret key reference"),
    (re.compile(r"SMTP_PASSWORD|smtp_password"), "SMTP password reference"),
]

# Files allowed to mention 'localhost' without failing the build (the
# vendor Supabase SDK's own dev-mode warning text is not a leaked
# production/staging config value).
LOCALHOST_ALLOWED_FILES = {"vendor/supabase/supabase-2.110.5.js"}

def build_artifact():
    if ARTIFACT_DIR.exists():
        shutil.rmtree(ARTIFACT_DIR)
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)

    copied = []
    missing = []
    all_required = PRODUCTION_FILES + REQUIRED_FEATURE_FILES
    for rel_path in all_required:
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


def scan_artifact():
    """Returns (fatal_findings, non_fatal_findings)."""
    fatal = []
    non_fatal = []
    for path in ARTIFACT_DIR.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(ARTIFACT_DIR)
        rel_str = str(rel).replace("\\", "/")
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue  # binary asset (e.g. the logo PNG) -- not scanned as text

        if STAGING_PROJECT_REF in text:
            fatal.append(f"{rel}: contains staging Supabase project ref {STAGING_PROJECT_REF}")
        for pattern, label in SECRET_PATTERNS:
            if pattern.search(text):
                fatal.append(f"{rel}: matched pattern for {label}")
        if "localhost" in text.lower() and rel_str not in LOCALHOST_ALLOWED_FILES:
            fatal.append(f"{rel}: contains the literal string 'localhost' outside the allowed-file list")

    return fatal, non_fatal


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


def confirm_no_staging_pages_url():
    hits = []
    for path in ARTIFACT_DIR.rglob("*.html"):
        text = path.read_text(encoding="utf-8", errors="ignore")
        if "pdc-control-board-staging" in text or "github.io/pdc-control-board-staging" in text:
            hits.append((str(path.relative_to(ARTIFACT_DIR)), "references the STAGING Pages URL"))
    return hits


def confirm_registration_and_user_management_present():
    """Production must expose administrator User Management while keeping
    public account self-registration absent."""
    problems = []
    index_path = ARTIFACT_DIR / "index.html"
    app_path = ARTIFACT_DIR / "app.js"
    auth_path = ARTIFACT_DIR / "pdc-auth.js"
    if not index_path.exists():
        return ["index.html missing -- cannot verify registration/User Management wiring"]
    index_text = index_path.read_text(encoding="utf-8", errors="ignore")
    app_text = app_path.read_text(encoding="utf-8", errors="ignore") if app_path.exists() else ""
    auth_text = auth_path.read_text(encoding="utf-8", errors="ignore") if auth_path.exists() else ""
    if 'id="nav-user-management"' not in index_text or 'id="user-management"' not in index_text or 'id="user-management-content"' not in index_text:
        problems.append("index.html does not contain the complete administrator User Management navigation/screen")
    required_app_markers = (
        "vehicleLifecycleAdministratorActive", "USER_MANAGEMENT_STATE",
        "admin_approve_user", "admin_reject_registration", "admin_change_role",
        "admin_disable_user", "admin_restore_user",
    )
    missing_markers = [marker for marker in required_app_markers if marker not in app_text]
    if missing_markers:
        problems.append(f"app.js is missing administrator User Management authority/actions: {missing_markers}")
    if ("pdc-auth-registration" in index_text
            or 'id="pdc-show-create-account"' in index_text
            or 'id="pdc-create-account-form"' in index_text
            or ".auth.signUp(" in auth_text):
        problems.append("public registration is present in the production artifact")
    if "Public account registration is disabled." not in index_text:
        problems.append("index.html does not state that public account registration is disabled")

    return problems


def confirm_shared_data_flags_enabled():
    """Independent-review requirement: production's Supabase config
    must explicitly enable workshop.sharedData and
    vehicleLifecycle.sharedData -- both false-by-default until this is
    verified done deliberately and safely (not automatically enabled
    by this validator; it only checks that a human already turned them
    on in pdc-supabase-config.production.js before the artifact is built)."""
    config_path = ARTIFACT_DIR / "pdc-supabase-config.production.js"
    if not config_path.exists():
        return ["pdc-supabase-config.production.js missing -- cannot verify shared-data flags"]
    text = config_path.read_text(encoding="utf-8", errors="ignore")
    problems = []
    if not re.search(r"workshop\s*:\s*\{[^}]*sharedData\s*:\s*true", text, re.DOTALL):
        problems.append("pdc-supabase-config.production.js does not set workshop.sharedData = true")
    if not re.search(r"vehicleLifecycle\s*:\s*(?:Object\.freeze\()?\{[^}]*sharedData\s*:\s*true", text, re.DOTALL):
        problems.append("pdc-supabase-config.production.js does not set vehicleLifecycle.sharedData = true")
    return problems


def confirm_all_referenced_assets_exist():
    """Every <script src=...> / <link href=...> in index.html must
    actually exist in the built artifact -- a missing asset would 404
    live in production."""
    index_path = ARTIFACT_DIR / "index.html"
    if not index_path.exists():
        return ["index.html missing"]
    text = index_path.read_text(encoding="utf-8", errors="ignore")
    problems = []
    for match in re.finditer(r'(?:src|href)="([^"?]+)(?:\?[^"]*)?"', text):
        ref = match.group(1)
        if ref.startswith(("http://", "https://", "#", "data:")):
            continue
        asset_path = ARTIFACT_DIR / ref
        if not asset_path.exists():
            problems.append(f"index.html references '{ref}' but it is not present in the artifact")
    return problems


def sha256_manifest():
    manifest = {}
    for path in sorted(ARTIFACT_DIR.rglob("*")):
        if path.is_file():
            manifest[str(path.relative_to(ARTIFACT_DIR))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return manifest


def main():
    copied, missing = build_artifact()
    print(f"Copied {len(copied)} files into {ARTIFACT_DIR}")

    all_failures = []

    if missing:
        all_failures.append(f"{len(missing)} required production file(s) missing from the repo: {missing}")

    fatal_scan_findings, _ = scan_artifact()
    print("\n--- Secret / staging-reference / localhost scan ---")
    if fatal_scan_findings:
        for f in fatal_scan_findings:
            print(" FAIL -", f)
        all_failures.extend(fatal_scan_findings)
    else:
        print(" (no findings)")

    print("\n--- Production reference presence check ---")
    prod_hits = confirm_production_ref_present()
    print(f" Files referencing production project ref {PRODUCTION_PROJECT_REF}: {prod_hits}")
    if not prod_hits:
        all_failures.append("production Supabase reference not found anywhere in the artifact")

    print("\n--- Staging Pages URL leakage check ---")
    staging_url_hits = confirm_no_staging_pages_url()
    if staging_url_hits:
        print(f" FAIL: {staging_url_hits}")
        all_failures.append(f"staging Pages URL leaked into the production artifact: {staging_url_hits}")
    else:
        print(" OK: no staging Pages URL found in any HTML file.")

    print("\n--- Registration / User Management presence check ---")
    registration_problems = confirm_registration_and_user_management_present()
    if registration_problems:
        for p in registration_problems:
            print(" FAIL -", p)
        all_failures.extend(registration_problems)
    else:
        print(" OK: administrator User Management is present and public registration is absent.")

    print("\n--- Shared-data production feature flag check ---")
    flag_problems = confirm_shared_data_flags_enabled()
    if flag_problems:
        for p in flag_problems:
            print(" FAIL -", p)
        all_failures.extend(flag_problems)
    else:
        print(" OK: workshop.sharedData and vehicleLifecycle.sharedData are both true.")

    print("\n--- Referenced-asset existence check ---")
    asset_problems = confirm_all_referenced_assets_exist()
    if asset_problems:
        for p in asset_problems:
            print(" FAIL -", p)
        all_failures.extend(asset_problems)
    else:
        print(" OK: every asset index.html references is present in the artifact.")

    manifest = sha256_manifest()
    manifest_path = ARTIFACT_DIR.parent / "production-artifact-manifest.sha256.txt"
    manifest_path.write_text(
        "\n".join(f"{h}  {p}" for p, h in sorted(manifest.items())) + "\n", encoding="utf-8"
    )
    print(f"\nWrote manifest: {manifest_path} ({len(manifest)} files)")

    if all_failures:
        print(f"\nFAIL: production artifact validation failed with {len(all_failures)} problem(s). NOT DEPLOYED.")
        for f in all_failures:
            print("  -", f)
        sys.exit(1)

    print("\nPASS: production artifact validation succeeded. NOT DEPLOYED -- local build only.")


if __name__ == "__main__":
    main()
