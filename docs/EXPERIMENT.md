# Private Submodule PackageSet Experiment

## Goal

Validate one narrow architecture slice before implementing a package manager:

```text
private reusable repository
        |
        | Git submodule / exact gitlink revision
        v
Learn.PackageSet.PackageManager
        |
        | materialize
        v
Learn.PackageManager/Assets/CraftyRacoon/Managed/<component>
```

The PackageSet checkout is the canonical editable source authority. The Unity project copy is a distribution projection.

## Explicitly out of scope

- UPM for private repositories
- package registries
- dependency solving
- installer UI
- GitHub Releases
- automatic authentication
- multi-package ownership

UPM is reserved for public repositories and will be evaluated separately.

## Repository placement

For this experiment, clone the repositories as siblings inside one container directory:

```text
<container>/
  Learn.PackageManager/
    Assets/
    ProjectSettings/
  Learn.PackageSet.PackageManager/
```

The manifest points to `../Learn.PackageManager`, which resolves to the sibling Unity project root.

## Add the first private source

Choose one small private reusable repository with few dependencies.

From the PackageSet repository:

```powershell
git submodule add <PRIVATE_REPOSITORY_URL> Sources/<Canonical.Identity>
git commit -m "Add private source experiment"
```

Then add an entry to `package-set.json`:

```json
{
  "identity": "Module.Example",
  "sourcePath": "Sources/Module.Example",
  "projectionName": "Module.Example"
}
```

Do not duplicate the expected commit SHA in JSON. The PackageSet gitlink is the revision authority.

## Commands

```powershell
./Tools/packageset.ps1 validate
./Tools/packageset.ps1 materialize
./Tools/packageset.ps1 use-development
./Tools/packageset.ps1 use-distribution
```

Pass an identity as the second argument to operate on one entry.

## Required invariants

### Validate

Must fail when:

- submodule is not initialized;
- checkout HEAD differs from the PackageSet gitlink;
- source path is missing;
- projection escapes `Assets/CraftyRacoon/Managed`.

### Materialize

Must additionally fail when the private source working tree is dirty.

A successful materialization:

- copies the complete source tree except Git metadata;
- writes `.packageset-provenance.json`;
- only replaces the declared managed projection directory;
- does not touch project-owned Assets, Scenes, or ProjectSettings.

### Development mode

`use-development` replaces the managed physical directory with an NTFS junction pointing at the canonical submodule checkout.

This is an experiment, not an accepted final implementation. Record Unity AssetDatabase behavior and both repositories' `git status`.

### Distribution mode

`use-distribution` removes the junction and rematerializes from a clean exact gitlink revision.

## Manual validation gates

1. Add one private submodule and manifest entry.
2. `validate` passes.
3. `materialize` creates the managed Unity projection and provenance.
4. Unity 6000.3.20f1 imports and compiles it.
5. Move or rename the PackageSet checkout away; Unity still opens and compiles from the committed projection.
6. Restore PackageSet and run `use-development`.
7. Edit the private source; Unity detects the edit and the source repository shows the change.
8. Record whether the Unity project repository remains acceptably clean while the junction is active.
9. With dirty source, `materialize` must fail.
10. Commit the source change, advance the PackageSet gitlink, materialize again, and verify provenance revision.
11. Fresh-clone only `Learn.PackageManager` and confirm it works without private source credentials.

## Go / No-Go

The architecture is viable if canonical private source ownership, exact-revision materialization, distribution independence, and clean source provenance all pass.

A junction failure only rejects that development-switch implementation; it does not reject PackageSet itself.
