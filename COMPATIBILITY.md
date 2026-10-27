# Firmware compatibility

Which robot firmware (Valetudo) each VacuPilot release was tested against, and
which newer firmware features the app does not cover.

## Compatibility matrix

| VacuPilot | Build | Date | Minimum | Tested against | Evidence |
|---|---|---|---|---|---|
| 1.1.3 | 108 | 2026-10-24 | 2024.06.0 | 2026.10.0 (source) | No device test; carpet id as a number (Midea) against unit tests and the simulated robot |
| 1.1.2 | 107 | 2026-10-22 | 2024.06.0 | 2026.10.0 (source) | No device test; API comparison 2026.08.0 → 2026.10.0, new values via unit tests |
| 1.1.0 | 104 | 2026-10-07 | 2024.06.0 | 2026.08.0 | Device test on a Roborock S5 Max; carpet and map annotations only against the simulated robot |
| 1.0.0 | 99 | 2025-12-20 | 2024.06.0 | 2026.02.0 · 2026.05.0 | Live OTA test on two robots |

The minimum is not enforced: the app follows the robot's capability list, so
older firmware shows up as missing features, not as an error.

## Firmware features since 2026.05.0

| Firmware | Feature | In VacuPilot |
|---|---|---|
| 2026.07.0 | Carpet as room floor material | 1.1.0 |
| 2026.07.0 | Map annotations (threshold, curtain, ramp) | 1.1.0 |
| 2026.08.0 | Camera live view | Not planned |
| 2026.10.0 | MQTT settings without interface switches | 1.1.0 (1.0 cannot load or save the MQTT page on 2026.10.0) |
| 2026.10.0 | Mop dock drying times `5h` and `quiet` | After 1.1.1 |
| 2026.10.0 | Roller mop dock loosener (consumable `brush`/`secondary`) | After 1.1.1 |

## Vendor differences

- **Midea** sends the carpet id in the map as a number, Dreame as text. Before
  1.1.3 this left the map empty; since then both are read and an unreadable map
  element is skipped instead of dropping the whole map.

## Test devices

Two Roborock S5 Max. Floor materials and map annotations cannot be tested on
them (the S5 Max does not report these capabilities; carpet and annotations
exist only on Dreame so far); everything else can.
