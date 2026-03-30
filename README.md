# libn3ds (fork)

libn3ds is a common library for 3DS ARM9/ARM11 bare metal projects.

See the original project [here](https://github.com/profi200/libn3ds).

This fork adds support for a GBA cheat engine, enabling Action Replay (PARv3) cheat codes in open_agb_firm.

## Changes

### IPC command: `IPC_CMD9_SET_GBA_CHEATS`

A new IPC command (`ipc_handler.h`, `ipc_handler.c`) allows the ARM11 to send decoded cheat data to the ARM9. The ARM9 handler receives an array of cheat entries (up to `LGY_MAX_CHEATS` = 25) and stores them in global buffers (`g_cheatData`, `g_cheatCount`) for use during GBA boot.

### ARM7 cheat engine (`lgy7_code.s`)

A new ARM7 IRQ handler (`_gba_cheat_irq_handler`) is added to the existing GBA stub code. When cheats are active, it replaces the BIOS IRQ dispatcher by patching the GBA IRQ vector. On each VBlank interrupt, the handler iterates a cheat table in IWRAM (`0x03007ED0`) and applies constant memory writes (8/16/32-bit), then forwards to the game's own IRQ handler.

### Cheat engine installation (`lgy9.c`)

During `setupBiosOverlay()`, if cheats were received via IPC, the ARM9:

1. Copies the cheat engine code to GBA IWRAM at `LGY9_CHEAT_ENGINE_LOC` (`0x03007E50`), after the existing boot stub.
2. Writes the cheat count and entries to `LGY9_CHEAT_DATA_LOC` (`0x03007ED0`).
3. Patches the GBA IRQ vector (`a7_vector[6..7]`) to redirect to the cheat engine instead of the BIOS dispatcher.

### Memory layout constants (`lgy9.h`)

New defines for the cheat engine and data table locations in GBA IWRAM:

| Constant | GBA address | Description |
|---|---|---|
| `LGY9_CHEAT_ENGINE_LOC` | `0x03007E50` | Cheat engine code |
| `LGY9_CHEAT_DATA_LOC` | `0x03007ED0` | Cheat count + entry table |

### Public API (`lgy_common.h`)

- `LGY_MAX_CHEATS` (25) -- maximum cheat entries per game.
- `Result LGY_setGbaCheats(const u32 *cheatData, u32 cheatCount)` -- sends cheat data from ARM11 to ARM9 via IPC.
