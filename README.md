# midisista

Plain Norns script starter built from the MIDI loop engine in `midididi`.

## What It Includes

- MIDI CC loop capture and playback through `reflection`
- Plain script `init()` and `cleanup()` instead of a Norns mod wrapper
- Hybrid UI: params for setup and mapping, screen for live status
- Eight starter target params that can be MIDI-mapped through Norns

## Controls

- `E1`: select page
- `E2`: select field or target
- `E3`: edit the selected value
- `K2`: jump to monitor page
- `K3`: jump to targets page

## Pages

- `DEVICE`: choose the active MIDI device and whether that device selection is persisted
- `MONITOR`: view the latest incoming MIDI event and recording state
- `TARGETS`: tweak the starter target params and see which mapped target is recording

## Mapping Flow

1. Start the script.
2. Set the MIDI device on the `DEVICE` page.
3. Open `PARAMS` and map one or more `midisista target` params to MIDI CC.
4. Send note on/off plus CC on the same device, channel, and CC id.
5. Recorded CC playback is sent back out to the selected MIDI device.

## Clock Behavior

- `midisista` does not directly sync to external MIDI clock.
- The script only reacts to note on/off and CC input for loop control and captured data.
- Loop capture and playback are handled by the Norns `reflection` library, which is clock-synced within the Norns clock domain.
- In practice, this means playback timing comes from `reflection` / Norns clock behavior rather than from explicit MIDI clock message handling in this script.

## Notes

- This starter keeps the current engine behavior from `midididi`: single device, absolute CC values, and note/CC id matching.
- The script does not parse MIDI clock transport messages such as clock, start, continue, or stop.
- The script UI is intentionally small so it can be expanded without reworking the engine integration.