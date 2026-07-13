# Azure Static Web App setup

This project contains an optional Azure Static Web Apps configuration with Microsoft login protection. Its presence is not a production platform decision. Evaluate it alongside other supported options using the requirements in `BACKEND_MIGRATION_PLAN.md`.

## What is already in the repo

- `staticwebapp.config.json` protects the site with Azure Static Web Apps authentication.
- Unauthenticated users are redirected to Microsoft login at `/.auth/login/aad`.
- The config is ignored by GitHub Pages, so the existing GitHub Pages site is not changed.

## Optional Azure setup reference

1. Create an Azure Static Web App.
2. Deployment source: GitHub.
3. Repository: `BTNew/pdc-control-board`.
4. Branch: `main`.
5. Build preset: Custom.
6. App location: `/`.
7. API location: leave blank.
8. Output location: leave blank.
9. Region: choose the closest available region.

Azure will create a GitHub Actions workflow with a deployment token stored as a GitHub secret.

## Microsoft 365 / Entra ID access control

For proper business security:

1. Restrict sign-in to the company Microsoft tenant.
2. Prefer a Microsoft 365 security group, for example `PDC Control Board Users`.
3. Assign only approved staff to that group.
4. Avoid adding secrets, passwords, connection strings, or API keys to the public repo.

## Important notes

- GitHub Pages is public by design. Keep it for demo/non-sensitive use only.
- The Azure Static Web App URL should become the private staff link.
- Shared saving should be added later using a protected backend such as SharePoint Lists, Dataverse, Azure SQL, or another private database.
- Do not store customer/business data directly in public JavaScript files.
- Do not deploy this option as production until authentication scope, data storage, audit, backup, support and recovery requirements have been approved.
