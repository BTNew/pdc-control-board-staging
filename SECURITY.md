# Security

## Project type
This is a static GitHub Pages/localStorage application. It should not require server credentials, API keys, customer secrets or privileged tokens in the repository.

## Rules
- Do not commit secrets, tokens, passwords, cookies, customer private data or environment files.
- Do not add analytics, advertising pixels, telemetry, hidden redirects, external trackers or third-party scripts without explicit approval.
- Do not expose private customer/business data on public pages.
- Do not change DNS, GitHub Pages source, custom domain, repository visibility or access permissions without explicit approval.
- Do not add destructive data-clearing behaviour without explicit approval and backup/export wording.
- Keep all workflow changes small, reviewable and tested before deployment.

## Browser scripts and network calls

This package does not load third-party CDN scripts, analytics, trackers, or hidden network calls.

Optional integrations remain defensive:

- QZ Tray/Zebra printing only runs when a local QZ Tray object is already available in the browser environment; otherwise the app shows a clear unavailable message.
- PDF text extraction uses the app's existing fallback path when PDF.js is not available.

Do not add third-party scripts, analytics, trackers, or hidden network calls without explicit approval. If QZ Tray or PDF.js are required later, vendor approved pinned files locally rather than loading them from a public CDN.

## Data handling
- Vehicle data is stored in browser localStorage on the device using the site.
- Users should export backups before clearing browser data or switching PCs.
- The live GitHub Pages site only hosts static files; it does not provide shared server-side storage.
- GitHub Pages does not enforce `staticwebapp.config.json`; that configuration applies only when served by Azure Static Web Apps.
- The bundled `data.js` baseline contains operational business/customer information. Do not deploy that baseline to an unauthenticated public host.
- Use the zero-vehicle import-test build, synthetic fixtures or anonymized data for public demonstrations.

## Production hosting direction

- Production access requires centrally managed authentication and authorization before HTML, API data, attachments or exports containing operational information are returned.
- The shared backend must enforce server-side validation, permanent vehicle identity, transactional writes, concurrency conflict handling, audit events and tested backups.
- Do not select or embed a vendor-specific production dependency until the requirements and security review in `BACKEND_MIGRATION_PLAN.md` are approved.

## Deployment checks
Before any live deployment:
- Check git diff for accidental secrets or private data.
- Run syntax and workflow validation scripts.
- Run a local browser console check.
- Confirm the live site builds and has no browser console errors after push.
