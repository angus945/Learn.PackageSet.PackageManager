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


## Development-mode Git semantics

Development mode deliberately replaces the committed physical projection with an NTFS junction to the canonical source checkout.

While that junction is active:

- the source repository remains the only reusable source commit authority;
- the Unity project repository may report managed files as modified, deleted, or untracked;
- that Unity-project dirty state is expected because its index still represents the committed distribution snapshot while the filesystem exposes live development source;
- do not stage or commit managed projection changes from the Unity project while development mode is active;
- Unity-generated metadata inside the source checkout is governed by the source repository's Unity/.gitignore policy.

The important invariant is convergence, not a clean Project working tree during development:

```text
development source change
    -> source commit
    -> PackageSet gitlink advance
    -> use-distribution
    -> exact-revision materialization
    -> review/commit Project distribution diff
```

A valid lifecycle ends with the physical distribution projection matching the PackageSet gitlink revision and no junction remaining.

## Full lifecycle gate

1. Start from a committed distribution projection.
2. Switch to `use-development`.
3. Modify canonical source and verify Unity consumes the change immediately.
4. Commit and push the canonical source change.
5. In the PackageSet repository, stage the submodule gitlink change and commit it.
6. Run `validate`; it must resolve the new exact revision.
7. Run `use-distribution`; it must replace the junction with a physical projection from the clean exact revision.
8. Verify the Unity project still compiles.
9. Verify Project Git now shows only the intended materialized distribution diff.
10. Commit the Project projection update.
11. Fresh-clone the Project only and verify it works without PackageSet/private-source access.
