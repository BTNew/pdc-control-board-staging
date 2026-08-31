# Transport bundle contents

The full `.69` transport asset is published separately with the private Recovery Pack release because it contains the complete 3,351-file Python/runtime inventory and is too large for the pack source tree.

Asset: `pdc-monitor-staging-m502-2026.08.69.tar.gz`

Verify before extraction/use:

- archive SHA-256: `c269de2f46312e8d85bb4f91ca0b0702e8d51ec620b86c01619af2fed446a22c`
- archive size: `119965123` bytes
- embedded release manifest SHA-256: `fa528d8d1ce405b430dc265ded7dca69cc7b49e8d190b90d9e55576b32a1a823`
- parent `.68` manifest SHA-256: `f55c8ba1f06b342fd3205f5a287f4793cb242d886759218a7470482c7c36f18b`
- bridge SHA-256: `d19f1ee93b5c45169d10e77956677909d2b5844e4aea3ce2e028c0b2edc30071`

The bundle contains the reviewed installer, elevated installer, health check, VerifyOnly runner/bootstrap, current-head preflight, active runner and repair controls. No mailbox password, runtime password, Supabase service key, DPAPI secret or Production credential belongs in the bundle.

The installer requires one protected owner UAC approval on a fresh Windows PC. It must leave the task disabled. Only the later guarded activation step enables PT5M, and that step never starts it.
