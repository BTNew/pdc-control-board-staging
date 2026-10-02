# Staging runtime publishing

This prepared workflow changes only the staging website artifact. It does not change production, Supabase, PDC vehicle records, workshop bookings or backup storage.

## Why the publishing source must change

The current successful Pages run uses the GitHub-generated `dynamic/pages/pages-build-deployment` workflow. Its checkout is uploaded from `.` with only `.git` and `.github` excluded. It publishes evidence, migrations, handovers and other repository material alongside the website. Adding a tracked workflow while retaining that source does not stop the generated root upload.

The replacement is `.github/workflows/pages-runtime.yml`. It runs the top-level website tests and existing privileged-token scan, builds an explicit 118-file public runtime, and uploads only `_site`. It refuses to deploy until GitHub reports `build_type: workflow`. Pull requests build and validate an artifact but cannot deploy.

## Activate after review

1. Review and merge the prepared staging changes to `main`.
2. In the staging repository, open **Settings → Pages → Build and deployment → Source** and select **GitHub Actions**. This requires the repository permission described in GitHub's publishing-source documentation. Do not select a branch or root folder.
3. Let any already-running generated Pages deployment finish. Avoid a stale root artifact deploying after the clean artifact.
4. Run **Publish staging runtime website** on `main`, or use the next reviewed `main` push. Verify the build and deploy jobs complete successfully and the `github-pages` environment references this run.
5. Confirm `/`, `/sales/`, the PDF worker, printer bridge assets and the existing guide load. Confirm evidence, handover, migrations and backup-script paths no longer load from Pages. These checks concern the new artifact; they do not remove repository history or copies already obtained by others.

Do not grant workflow permissions to change Pages settings automatically. If the source guard returns HTTP 403/404, verify this repository's Pages setting and the workflow's Pages read permission. The guard fails safely; it never falls back to publishing the checkout.

## Maintain the explicit artifact

Run `node scripts/build_pages_runtime.js --validate` for a read-only validation. Use `node scripts/build_pages_runtime.js --output <new-or-empty-directory>` to produce a local artifact. The builder refuses nonempty outputs, symlinks, path traversal, privileged tokens, operational fallback rows, unreviewed public metadata and missing dependencies. It does not recursively delete directories or deploy.

The reviewed allowlist includes eight HTML entry points, all their local runtime assets, the deferred workshop/PDF modules and workers, QZ bridge, vendor licenses and the guide's five inspected training images. Those images show generic controls and an explicitly fictional training team. The rule-classification JSON is not referenced by the browser dependency graph and is not included. Only the existing read-only `scripts/stage2b_c4_browser_export.js` helper is retained from `scripts/`, because the main entry point loads it.

Add future dependencies explicitly after reviewing their contents and purpose. An added file reference fails the regression until the publication review is recorded in the allowlist. Do not copy a directory, infer publication from an extension, add customer records to fallback JavaScript, or include audits, recovery payloads, backend tools, tests or backup files.

## Official reference

- [GitHub custom Pages workflows](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
- [Configure the Pages publishing source](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
- [GitHub Pages REST API](https://docs.github.com/en/rest/pages/pages)

Prepared on 2026-10-02. The publishing-source change and clean deployment still require verification in GitHub; the local preparation alone does not close the exposure.
