# Sources

This directory contains canonical development checkouts for private reusable repositories.

Rules:

- Each managed source is added as a Git submodule.
- The PackageSet gitlink is the exact revision authority.
- Do not copy repositories into this directory as ordinary folders.
- Do not duplicate source commit SHAs in `package-set.json`.
- Public repositories may use UPM in a separate path; this experiment is private-submodule-only.
