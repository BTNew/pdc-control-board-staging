# Protected typed commissioning connector

The v2 pack does not consume the legacy `PDC_RECOVERY_INSTALL_COMMAND`. If an
operator requests installation, the deployment gateway must provide the
following protected, typed connector and keep it disabled until independent
review passes:

- `PDC_V2_TYPED_COMMISSIONING_CONNECTOR` — an absolute executable path supplied
  by the protected deployment store;
- `PDC_V2_STAGING_VIEWER_SECRET` — the least-authority current-state credential.

The connector must accept only a typed v2 bundle manifest and staging target. It
must reject shell fragments, Production targets, service-role/admin identities,
legacy queue/proposal formats and mailbox mutation. The shadow runtime itself
requires neither variable and performs no installation.

If the connector or Viewer secret is absent, the correct result is a fail-closed
provisioning blocker naming the missing secret/connector name only. Do not use a
legacy installer, hidden memory, another profile's credential, or a broad shell
command as a fallback.
