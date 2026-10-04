# Learn.PackageSet.PackageManager

Minimal PackageSet experiment for `angus945/Learn.PackageManager`.

## Scope

This repository is the source-composition authority for private reusable components used by the Unity experiment.

The first slice intentionally validates only:

1. private Git submodule as canonical editable source;
2. exact revision authority from the PackageSet gitlink;
3. materialization into the Unity project's managed projection boundary;
4. optional local development switching through an NTFS junction;
5. fresh Unity project operation without the PackageSet checkout.

UPM is explicitly out of scope for private repositories. Public repositories may use UPM in a separate experiment.

## Ownership

```text
Learn.PackageSet.PackageManager/
  Sources/<private-submodule>     canonical editable source

Learn.PackageManager/
  Assets/CraftyRacoon/Managed/   distribution projection only
```

Do not edit reusable code in the Unity projection and do not place project-owned content under the managed projection root.

See `docs/EXPERIMENT.md` before adding the first private submodule.
