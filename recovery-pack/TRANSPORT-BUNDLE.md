# Transport bundle contents

The full `.71` transport asset is published separately with the private Recovery Pack release because it contains the complete 3,359-file Python/runtime inventory and is too large for the pack source tree.

Asset: `pdc-monitor-staging-m502-2026.08.71.tar.gz`

Verify before extraction/use:

- archive SHA-256: `2e8d95bb842b37e59227e6e949d50e7a952f61c628e1ab4931da85ac5d1b151c`
- archive size: `119973501` bytes
- embedded release manifest SHA-256: `b68ba314cc91e0a3aa91d3c383d1cd19f5f56197bd94b2b92d61c60ea267322d`
- parent `.69` manifest SHA-256: `fa528d8d1ce405b430dc265ded7dca69cc7b49e8d190b90d9e55576b32a1a823`
- storage bridge SHA-256: `d19f1ee93b5c45169d10e77956677909d2b5844e4aea3ce2e028c0b2edc30071`
- processor SHA-256: `9b5db40c70e6340da7bb9413c27f87f5706ac7ece64e45cad8b79666b300f47f`
- active control SHA-256: `a98dbfeb8ca808f5795d05ba44017e6c08ab8d19a20b017c3793067b487f54a3`
- trust-values SHA-256: `641bd8b1f5cd367ba8b2bed1f9baf4984b43f175956d5570524c429b52587e2b`
- live staging head: `20260831380000`

The bundle contains the reviewed `.71` installer, elevated installer, verifier, receipt schema, venv contract, active bootstrap/dispatch/preflight controls and the exact storage-readback/quarantine repairs. It contains no mailbox password, runtime password, Supabase service key, DPAPI secret or Production credential.

The installer stages protected bundle/control/trust/venv/config trees, preserves `.68` and `.69`, updates the task only after readback gates pass, and never performs a manual task run or OneCycle.
