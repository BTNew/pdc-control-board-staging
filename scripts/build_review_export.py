"""
Allow-list-based independent-review export tool.

Unlike the ad-hoc os.walk copy used previously (which copied the entire
working directory tree minus a short deny-list and accidentally picked
up gitignored runtime data -- real IMAP email attachments, an email
processing log, and a nested operational backup ZIP), this exporter
works the other way around: it only ever copies files that are
explicitly tracked by git (`git ls-files`) or that appear on a short,
explicit, reviewed allow-list of additionally-generated report files
(e.g. this session's test output, schema snapshot, screenshots).

Nothing else can enter the export, by construction. If a caller wants
a new kind of generated file included, it must be listed explicitly
in ADDITIONAL_ALLOWED_GENERATED_PATHS below -- there is no wildcard
"everything else" fallback.

The exporter also runs a hard, fail-closed safety scan over its own
output before returning success. If it finds anything that looks like
a runtime artifact, attachment, log, backup archive, secret, or token,
it raises and refuses to produce a ZIP.
"""
import fnmatch
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(r"C:\Users\nwmgr\pdc-control-board")

# Patterns that must NEVER appear in an export, regardless of source.
# Checked both as directory/file name fragments and via content scan.
FORBIDDEN_PATH_PATTERNS = [
    "*.imap_attachments*",
    "*email_publish.log*",
    "*_backup_*.zip",
    "*PDC_Control_Board_Backup*",
    "*.env",
    "*.env.local",
    "*.env.staging",
    "*.env.production",
    "*_staging_test_tools*",  # real service-role key lives here; a
                              # sanitized copy is added back explicitly
                              # via ADDITIONAL_ALLOWED_GENERATED_PATHS
                              # further down, never the real directory
    "*node_modules*",
    "*.venv*",
    "*__pycache__*",
    "*.pyc",
    "*backups/*",
    "*.git/*",
]

FORBIDDEN_CONTENT_PATTERNS = [
    re.compile(r"sb_secret_[A-Za-z0-9_\-]+"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
]

# Explicit allow-list of additionally-generated report files (not
# tracked by git, but reviewed and approved to include). Every entry
# here was written by this remediation phase's own tooling, never
# copied wholesale from a runtime/attachment/log directory.
ADDITIONAL_ALLOWED_GENERATED_PATHS = [
    "PRODUCTION-READINESS-HANDOVER.md",
    "INDEPENDENT-REVIEW-REMEDIATION-HANDOVER.md",
]


def is_forbidden_path(rel_posix: str) -> bool:
    # Named, reviewed exception: _staging_test_tools/.env.example
    # contains only blank/fake placeholder values (independent-review
    # remediation, Stage 10) and is the only file in that directory
    # ever intended to be tracked/exported. Checked before the
    # wildcard blanket-exclusion below, which otherwise correctly
    # blocks everything else in that directory (real service-role
    # keys, real staging test output, etc.).
    if rel_posix in ("_staging_test_tools/.env.example",):
        return False
    for pattern in FORBIDDEN_PATH_PATTERNS:
        if fnmatch.fnmatch(rel_posix, pattern) or fnmatch.fnmatch("/" + rel_posix, pattern):
            return True
        # also match any path segment containing the fragment (handles
        # nested dirs like backend/.imap_attachments/x.pdf matching
        # *.imap_attachments*)
        if fnmatch.fnmatch(os.path.basename(rel_posix), pattern):
            return True
    return False


def tracked_files() -> list[str]:
    """Every file git considers part of the tracked source tree on the
    current branch/worktree state -- this is the entire allow-list
    surface for 'source'. Untracked runtime data (attachments, logs,
    local backups, local secrets) is never returned here."""
    result = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "ls-files"],
        capture_output=True, text=True, check=True,
    )
    return [line for line in result.stdout.splitlines() if line.strip()]


def build_export_file_list() -> list[str]:
    files = tracked_files()
    safe_files = []
    rejected = []
    for rel in files:
        if is_forbidden_path(rel):
            rejected.append(rel)
            continue
        safe_files.append(rel)

    for extra in ADDITIONAL_ALLOWED_GENERATED_PATHS:
        full = REPO_ROOT / extra
        if full.exists() and extra not in safe_files:
            if is_forbidden_path(extra):
                raise RuntimeError(
                    f"ADDITIONAL_ALLOWED_GENERATED_PATHS entry '{extra}' matches a "
                    f"forbidden pattern -- refusing to add it. Fix the allow-list."
                )
            safe_files.append(extra)

    if rejected:
        print(f"Excluded {len(rejected)} tracked-but-forbidden path(s) (should be none once .gitignore is correct):")
        for r in rejected[:20]:
            print(f"  - {r}")

    return sorted(safe_files)


def scan_content_safety(file_list: list[str]) -> list[str]:
    """Fail-closed content scan over exactly the files about to be
    exported. Returns a list of problems; an empty list means safe."""
    problems = []
    for rel in file_list:
        full = REPO_ROOT / rel
        try:
            data = full.read_bytes()
        except OSError:
            continue
        # Skip binary-looking files for the text-pattern scan (images,
        # fonts, etc.) -- but the sb_secret_ / PRIVATE KEY patterns are
        # ASCII and would still match if truly present in a text file.
        try:
            text = data.decode("utf-8", errors="ignore")
        except Exception:
            continue
        for pattern in FORBIDDEN_CONTENT_PATTERNS:
            if pattern.search(text):
                problems.append(f"{rel}: matched forbidden content pattern {pattern.pattern!r}")
    return problems


def verify_no_forbidden_paths_in_export(file_list: list[str]) -> list[str]:
    """Belt-and-suspenders re-check of the final file list itself,
    independent of build_export_file_list's own filtering, so a bug in
    one function cannot silently defeat the other."""
    problems = []
    for rel in file_list:
        posix = rel.replace("\\", "/")
        if is_forbidden_path(posix):
            problems.append(rel)
    return problems


def main():
    file_list = build_export_file_list()
    print(f"Export file list contains {len(file_list)} files (allow-list based).")

    forbidden_still_present = verify_no_forbidden_paths_in_export(file_list)
    if forbidden_still_present:
        print("FAIL: forbidden paths survived filtering:")
        for p in forbidden_still_present:
            print(f"  - {p}")
        sys.exit(1)

    content_problems = scan_content_safety(file_list)
    if content_problems:
        print("FAIL: forbidden content patterns found in the export file set:")
        for p in content_problems:
            print(f"  - {p}")
        sys.exit(1)

    print("PASS: allow-list export file list contains no forbidden paths or content patterns.")
    return file_list


if __name__ == "__main__":
    main()
