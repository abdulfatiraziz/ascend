# Ascend avatar study

This is the earlier faceless Blender study, retained as legacy source. Ascend 0.5
uses [Abdul's supplied portrait renders](abdul/README.md) instead. The GLBs and
Three.js runtime described below no longer ship in the app bundle.

A first Blender asset study for the local macOS growth tracker. All three states
use the same body. Progress changes the finish and light details; it does not
claim to predict a physical transformation.

## Deliverables

- `ascend-avatar-study.blend` — editable scene with three avatar collections,
  display plinths, studio lights, camera and comparison typography.
- `ascend-titanium.glb` — satin titanium foundation state.
- `ascend-obsidian.glb` — dark graphite state.
- `ascend-ascendant.glb` — pearl alloy with violet light inlays.
- `renders/ascend-avatar-study.png` — rendered comparison of the three finishes.
- `build-stats.json` — exported asset sizes.

Runtime GLBs contain only the avatar. The studio, plinth, camera and labels are
excluded. The character is **not rigged or animated** yet. These are appearance
studies, ready for rotation and material/light effects in a viewer.

The exports use glTF's Y-up coordinates and meter units, with the origin near
the feet. Center the loaded model using its bounding box before placing it in
the app's avatar stage. The body, head, collar and inlays remain separate meshes
so their materials can be controlled independently.

## Source and license

The source is Blender Studio's **Human Base Meshes v1.4.1**, specifically the
`GEO-body_male_realistic` mesh. The official download listing and bundled
`README` identify this asset bundle as **CC0 / public domain**.

- Official listing: https://www.blender.org/download/demo-files/#assets
- Original archive: https://download.blender.org/demo/asset-bundles/human-base-meshes/human-base-meshes-bundle-v1.4.1.zip
- Original archive and extracted library are retained under `source/`.

The source library also contains an unrelated legacy text block mentioning the
Rain Rig's CC-BY license. This study imports **no Rain Rig, source armature or
animation** and does not include that text block. The source bundle README is
retained in the editable study for provenance.

## Customization

- Removed the original detailed head and created a smooth faceless shell.
- Adapted the source body into a fitted suit treatment.
- Added a collar, chest and shin inlays, shoulder bindings and a sternum crest.
- Created independent material states with a shared silhouette.
- Exported with one subdivision level for runtime and kept two for rendering.

## Rebuild

From the project root, with Blender on PATH:

```sh
blender --background --factory-startup --disable-autoexec --python scripts/build_avatar.py
```

Created and rendered with Blender 5.2.2 LTS. No account, paid assets or remote
rendering service is required.
