# Kyoto & the Midnight Signal — connected exploration build (v0.2)

A playable opening chapter about a programmer and his golden retriever Kyoto. This revision replaces the single-screen apartment with a much larger, scrolling apartment and two connected areas. It is an opening prototype, not the complete planned one-hour adventure.

[Play the published browser version](https://kyoto-midnight-signal-game.idealpig30.chatgpt.site)

This private repository contains the editable project, source artwork, audio, fonts, tests and hosting customizations. Godot import caches, export templates and compiled game downloads are generated locally and excluded from Git.

## What changed

- A lower, three-quarter painted environment and a close follow camera. At the default zoom the viewport shows roughly 580 × 386 map pixels out of a 1536 × 1024 map. Most of the apartment is initially off-screen.
- A larger apartment with a living area, kitchen, workbench and storage nook.
- A shared hall and a courtyard, connected through bidirectional doors.
- A power-cell repair that opens the garden exit, and three moon pieces that open the greenhouse.
- Nine extra discoveries. Several require Kyoto to sniff before they can be collected; others are tucked into corners that start off-camera.
- Per-room navigation and persistent pickups, repaired machinery, visited rooms, hidden-object reveals and camera zoom.
- An adjustable local zoom (LB/RB or -/+). Even the widest setting is a scrolling view.

## Play the download

**Browser:** extract the entire release folder and run `python3 play.py` (Windows: `python play.py`). Python 3 is required; no packages are needed. The launcher opens a local browser page. Keep its terminal open while playing. Directly opening `web/index.html` with `file://` will not run the game.

**Steam Deck / Linux x86-64:** launch `linux/kyoto.x86_64`. If necessary, mark it executable with `chmod +x linux/kyoto.x86_64`. Add it as a non-Steam game in Desktop Mode and use the standard Gamepad controller layout. This native Linux build does not require Proton.

**Web hosting:** the files in `web/` can be served by a static HTTPS host. Serve `.wasm` as `application/wasm`. This single-threaded export does not need cross-origin isolation headers.

## Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Walk | WASD / arrows | Left stick / D-pad |
| Interact / throw | E / Space | A |
| Ask Kyoto / sniff | Q | X |
| Pet Kyoto | F | Y |
| Zoom | - / + | LB / RB |
| Pause | Esc | Menu / Start |
| Menus | Arrows + Enter | D-pad + A |

Click visible floor to walk there. The camera follows automatically. Asking Kyoto gives a short trail; it does not expose the full map. Nearby hidden objects make him investigate. Controller disconnection and application focus loss pause the game. Some browsers need an initial click/button press before detecting a controller or starting audio.

## Main route (spoilers)

1. Take Kyoto's ball and throw it twice. On the second throw it rolls beneath the desk.
2. Follow Kyoto to the desk and ask him to sniff. Take the sphere he discovers and investigate the monitor.
3. Cross the apartment to collect the leash beside the door. Enter the shared hall.
4. The garden exit needs power. Search the apartment workbench for a power cell and fit it into the hall's maintenance cart. You can return through every unlocked doorway.
5. Collect a moon piece from the apartment's storage chest, another revealed by Kyoto near the hallway bench/plant, and a third from the courtyard sundial.
6. Place all three at the greenhouse door. The next chapter is teased below it. You can keep exploring afterward.

The repair component and moon pieces can also be discovered before you reach their locked doors. No combat, timers or fail states. Optional discoveries include a toy robot, a tucked-away photo, a drink, a cassette, an old mailbox, a toolbox, a garden nest, seeds and the far archway.

## Saves

Progress is local to the browser or Linux user account, with no cloud sync. The launcher uses a stable localhost port so browser saves survive later launches. Clearing browser storage removes saves. Checkpoints are written after meaningful interactions and room transitions. Transient fetch/search actions resume at stable checkpoints.

Version 2 saves use `exploration-v2.json`; the previous `opening-v1.json` can be read to preserve opening-story progress when continuing. Original v1 save files are left intact. Starting a new game asks before replacing the current v2 save.

## Develop

Open `project.godot` in Godot **4.6.3**, with GDScript and the Compatibility renderer. No add-ons or runtime network dependencies.

- `scenes/exploration.tscn`: current entry scene.
- `scripts/exploration.gd`: connected room gameplay, follow camera, new interactions, persistent world state.
- `scripts/room_data.gd`: room textures, walkable geometry, objects and door coordinates.
- `scripts/apartment.gd`: reusable original input, menus, audio hooks and base opening systems.
- `scripts/story.gd`: opening progression and stable checkpoint logic.
- `scripts/actor.gd`: illustrated character atlas animation.
- `scripts/sound.gd`: interaction tones and ambient playback.
- `assets/rooms/`: full level backgrounds. These are maps; gameplay shows only a portion at once.
- `tests/exploration.cjs`: full keyboard walkthrough across all areas and save/reload checks.
- `tests/controller.cjs`: simulated standard-controller regression.
- `tests/v1/`: archived tests for the original scene, not the current entry point.

After cloning, open `project.godot` directly in Godot, or build from the repository root. Install Godot's matching export templates, then:

```sh
godot --headless --editor --import --path . --quit
mkdir -p build/web build/linux
godot --headless --path . --export-release Web build/web/index.html
godot --headless --path . --export-release Linux build/linux/kyoto.x86_64
```

Run the navigation/progression checks:

```sh
godot --headless --path . -- --smoke-test
```

Browser checks require Node.js, Playwright and Chromium. Install the development dependency with `npm install`, serve `build/web` on port 8765, then run `npm run test:browser` or `npm run test:controller`. Adjust the scripts' `/usr/bin/chromium` path for your machine. Screenshots default to `build/test-artifacts`, or the `KYOTO_TEST_OUTPUT` directory. `?qa=1` enables a local read-only `window.__kyoto` snapshot for assertions; it sends no data elsewhere.

## Verification and limits

The connected-world browser route was exercised with actual keyboard input at 1280 × 800: the camera pans into previously unseen areas, all three rooms connect both ways, the repair opens the garden, the sniff-gated moon piece can be found, pickups survive reload, and the greenhouse opens. Navigation checks cover every authored interaction point. Controller checks use a simulated browser gamepad; a physical Steam Deck and physical controllers were not available. No Deck Verified status is claimed.

Art uses painted 2D backgrounds and a directional character atlas, with zoom/panning rather than a rotatable 3D camera. Large background paintings soften at close zoom; furniture is mostly static. The remaining datacenter, shuttle and lunar chapters are future work.

## Rebuild the published web page

After exporting the Web preset, prepare a static-hosting bundle:

```sh
python3 tools/prepare_hosted_web.py
node tools/verify_hosted_web.cjs
```

The output is `build/hosted-web/`. Upload that directory to a static HTTPS host. This preserves the published page's fullscreen control and compressed engine download while generating the correct engine size for each export. The verifier confirms that decoding produces exactly the original WebAssembly bytes. Modern Chrome, Edge or Firefox is required.

The existing public play page remains independently hosted; pushing to this GitHub repository does not automatically deploy it.

## Notices

Environment art and character sheets were generated for this project from the agreed visual direction. Ambient audio and interaction tones were synthesized for the project. Godot and font notices are in `licenses/`. No public license has been assigned to the original code or artwork.
