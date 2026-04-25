# midisista

Plain Norns script starter built from the MIDI loop engine in `midididi`.

## What It Includes

- MIDI CC loop capture and playback through `reflection`
- Plain script `init()` and `cleanup()` instead of a Norns mod wrapper
- Hybrid UI: params for setup and mapping, screen for live status
- Sixty-four target params organized as 8 pages of 8 tracks
- Grid visualization for 64 tracks split across 8 pages (8 tracks per page)
- Optional midigrid support for MIDI-grid devices

## Controls

- `E1`: select page
- `E2`: select field or target
- `E3`: edit the selected value
- `K2`: jump to monitor page
- `K3`: jump to targets page, then cycle target pages when already on TARGETS

## Pages

- `DEVICE`: choose the active MIDI device and whether that device selection is persisted
- `MONITOR`: view the latest incoming MIDI event and recording state
- `TARGETS`: view 8 target rows per page (64 total across 8 pages) with per-row status, mapped channel/CC, and live loop values

## Mapping Flow

1. Start the script.
2. Set the MIDI device on the `DEVICE` page.
3. Open `PARAMS` and map one or more `midisista target` params to MIDI CC.
4. Send note on/off plus CC on the same device, channel, and CC id.
5. Recorded CC playback is sent back out to the selected MIDI device.
6. As loops are recorded, TARGET rows learn and display the active loop's mapped channel/CC and current value.

## TARGETS Behavior

- Each target row represents one visible loop slot (64 total; 8 rows per page across 8 pages).
- `st` shows `rec` while a loop is recording and `ply` while it is playing back.
- `ch/cc` shows the mapped MIDI channel and CC number for that row.
- `val` shows the most recent live CC value for that row during record or playback.
- `pg` footer shows the current TARGETS page.
- When a new loop is recorded, the next available target row is used for that loop's displayed mapping and value.
- TARGET row matching is learned from live callback data so displayed rows stay aligned with working loop playback.

## Grid Behavior

- Press any key in **column 16** (rightmost column) to cycle between pages.
- Pages advance through all 8 track banks (1-8, 9-16, ... , 57-64).
- Column 16 shows a dim page indicator: the current page row lights brighter than the others.
- On each page, each row maps to one target track (rows 1-8 on grid).
- Hold any row key in columns 1-15 to record CC into that row's target track.
- Releasing that row key stops recording and starts playback for that same track.
- Each row lights one LED in columns 1-15 based on the current CC value (`0..127` mapped to `1..16`).
- Brighter LEDs indicate active recording (`rec=15`) and medium LEDs indicate playback (`ply=10`).
- Dimmer LEDs indicate stored values on idle loops (`stored=6`).
- Pressing any grid key in a row (columns 1-15) also selects that target row on the norns TARGETS page.

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