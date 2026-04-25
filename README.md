# midisista

Plain Norns script starter built from the MIDI loop engine in `midididi`.

## What It Includes

- MIDI CC loop capture and playback through `reflection`
- Plain script `init()` and `cleanup()` instead of a Norns mod wrapper
- Hybrid UI: params for setup and mapping, screen for live status
- Thirty-two starter target params that can be MIDI-mapped through Norns
- Grid visualization for 32 tracks split across 4 pages (8 tracks per page)
- Fast O(1) event-to-target lookup via learned hash map for responsive grid performance
- Column 1 safe track selection (selects without affecting recording)
- Optional midigrid support for MIDI-grid devices

## Controls

- `E1`: select page
- `E2`: select field or target
- `E3`: edit the selected value
- `K2`: jump to monitor page
- `K3`: jump to targets page; press again while on targets to cycle display pages

## Pages

- `DEVICE`: choose the active MIDI device and whether that device selection is persisted
- `MONITOR`: view the latest incoming MIDI event and recording state
- `TARGETS`: view up to thirty-two target rows (4 visible at a time) with per-row status, mapped channel/CC, and live loop values

## Mapping Flow

1. Start the script.
2. Set the MIDI device on the `DEVICE` page.
3. Open `PARAMS` and map one or more `midisista target` params to MIDI CC.
4. Send note on/off plus CC on the same device, channel, and CC id.
5. Recorded CC playback is sent back out to the selected MIDI device.
6. As loops are recorded, TARGET rows learn and display the active loop's mapped channel/CC and current value.

## TARGETS Behavior

- Each target row represents one visible loop slot (32 total, shown 4 per screen view across 8 display pages).
- `st` shows `rec` while a loop is recording and `ply` while it is playing back.
- `ch/cc` shows the mapped MIDI channel and CC number for that row.
- `val` shows the most recent live CC value for that row during record or playback.
- When a new loop is recorded, the next available target row on the **currently selected grid page** is used.
- If the selected page is full, a new recording will not overflow to another page.
- TARGET row matching uses a fast event hash map so displayed rows stay aligned with working loop playback with minimal CPU overhead.
- The footer shows the current display page (e.g. `pg 2/8`).

## Grid Behavior

- The grid is organized as **4 pages of 8 rows** (32 targets total).
- **Column 16** is the page selector: press row 1 to go to page 1, row 2 for page 2, row 3 for page 3, row 4 for page 4.
- Column 16 shows a dim page indicator: the current page row lights brighter (level 8) than the inactive rows (level 2).
- On each page, rows 1-8 map to 8 target tracks for that page.
- **Column 1** (safe select): press to select that row's target track on the TARGETS screen without starting or affecting any recording. The TARGETS screen automatically navigates to the display page containing that track.
- **Columns 2-15** (record/hold): hold to record CC into that row's target track; releasing stops recording and starts playback.
- Each row lights one LED in columns 1-15 based on the current CC value (`0..127` mapped across 15 columns) with a crossfade blend between neighboring columns for smooth visual motion.
- Brighter LEDs indicate active recording (level 15), medium LEDs indicate playback (level 10), and dimmer LEDs indicate stored idle values (level 6).
- New auto-learned recordings are allocated to the first free slot on the currently selected grid page only.

## Midigrid Support

- If a native monome grid is connected on norns `GRID` port 1, the script uses it.
- If no native grid is detected, the script tries to load midigrid automatically.
- Preferred include order is `midigrid/lib/midigrid_2pages` (16x8 emulation), then `midigrid/lib/midigrid`.
- Install midigrid in your dust scripts folder so includes resolve at runtime.
- If using midigrid with a script that also expects MIDI input, set your MIDI device to a slot other than 1 (per midigrid notes).

## Clock Behavior

- `midisista` does not directly sync to external MIDI clock.
- The script only reacts to note on/off and CC input for loop control and captured data.
- Loop capture and playback are handled by the Norns `reflection` library, which is clock-synced within the Norns clock domain.
- In practice, this means playback timing comes from `reflection` / Norns clock behavior rather than from explicit MIDI clock message handling in this script.

## Notes

- This starter keeps the current engine behavior from `midididi`: single device, absolute CC values, and note/CC id matching.
- Same-device MIDI capture and playback are supported.
- Multiple CC loops can run at the same time when they use different mapped targets.
- The script does not parse MIDI clock transport messages such as clock, start, continue, or stop.
- The script UI is intentionally small so it can be expanded without reworking the engine integration.