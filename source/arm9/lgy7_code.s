/*
 *   This file is part of open_agb_firm
 *   Copyright (C) 2023 profi200
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "arm.h"
#include "asm_macros.h"

.syntax unified
.cpu arm7tdmi
.fpu softvfp



BEGIN_ASM_FUNC _gba_vector_overlay
	mov  r0, #1
	mov  r1, #0x4000000
	strb r0, [r1, #0x300]  @ "POSTFLG"
	ldr  pc, =0x3007E00

.pool
.global _gba_vector_overlay_size
_gba_vector_overlay_size = . - _gba_vector_overlay
END_ASM_FUNC

@ Must be located at 0x3007E00.
BEGIN_ASM_FUNC _gba_boot
	adr  r1, _gba_boot_thumb + 1  @ 0x3007E1D
	msr  CPSR_fsxc, #PSR_INT_OFF | PSR_SVC_MODE  @ Already set on reset.
	add  sp, r1, #0x6B  @ 0x3007E88
	msr  CPSR_fsxc, #PSR_INT_OFF | PSR_SYS_MODE
	add  sp, r1, #0x5B  @ 0x3007E78
	mov  r3, #0x4700000
	bx   r1

.thumb
_gba_boot_thumb:
	movs r0, #1
	str  r0, [r3]  @ Disable BIOS overlay.
	@ The original ARM7 stub waits 256 cycles here (for the BIOS overlay disable?).
	@ The original ARM7 stub waits 1677800 cycles (100 ms) here for LCD/LgyFb sync.
	@ The original ARM7 stub waits for REG_VCOUNT = 160 here.

	lsls r4, r0, #26  @ 0x4000000 Needed for "function" call 0xBC below.
	movs r0, #0xFF    @ Clear WRAM, iWRAM, palette RAM, VRAM, OAM
	                  @ + reset SIO, sound and all other registers.

.global _gba_boot_swi_a9_addr
_gba_boot_swi_a9_addr = . - _gba_boot + 0x80BFE00 @ location in ARM9 address space.
	swi  0x01       @ RegisterRamReset
	@ After BIOS intro REG_TM0CNT_L is set to 0xFF8C instead of 0.
	@ No other differences between direct boot and BIOS.

	movs r0, #0xBC  @ SoftReset (0xB4) but skipping r2 & r4 loading.
	movs r2, #0

	@ REG_VCOUNT should be 126 at ROM entry like after BIOS intro.
_gba_boot_vcount_lp:
	ldrb r1, [r4, #6]  @ REG_VCOUNT
	cmp  r1, #126      @ Loop until REG_VCOUNT == 126.
	bne  _gba_boot_vcount_lp

	bx   r0

.align 2
.global _gba_boot_size
_gba_boot_size = . - _gba_boot
END_ASM_FUNC


@ Cheat engine IRQ handler.
@ Replaces the BIOS IRQ dispatcher when cheats are active.
@ Installed at 0x03007E50 in GBA IWRAM via the IRQ vector overlay.
@ On each VBlank, iterates the cheat table at 0x03007ED0 and applies
@ constant memory writes, then forwards to the game's IRQ handler.
.arm
BEGIN_ASM_FUNC _gba_cheat_irq_handler
	@ Replicate BIOS IRQ dispatcher entry.
	stmdb sp!, {r0-r3, r12, lr}

	@ Check if VBlank is pending and enabled.
	mov   r0, #0x4000000
	ldrh  r1, [r0, #0x200]       @ REG_IE
	ldrh  r2, [r0, #0x202]       @ REG_IF
	ands  r2, r2, r1
	tstne r2, #1                  @ Bit 0 = VBlank
	beq   _cheat_call_game

	@ Load cheat table.
	ldr   r3, =0x03007ED0        @ Cheat data address in IWRAM.
	ldr   r12, [r3], #4          @ Cheat count.
	cmp   r12, #0
	beq   _cheat_call_game

_cheat_loop:
	ldr   r0, [r3], #4           @ Type (top nibble) + address (bottom 28 bits).
	ldr   r1, [r3], #4           @ Value.
	mov   r2, r0, lsr #28        @ Extract type nibble.
	bic   r0, r0, #0xF0000000    @ Mask to address.

	cmp   r2, #0
	streqb r1, [r0]              @ Type 0: 8-bit write.
	beq   _cheat_next
	cmp   r2, #1
	streqh r1, [r0]              @ Type 1: 16-bit write.
	beq   _cheat_next
	cmp   r2, #2
	streq r1, [r0]               @ Type 2: 32-bit write.

_cheat_next:
	subs  r12, r12, #1
	bne   _cheat_loop

_cheat_call_game:
	@ Forward to the game's IRQ handler (same as BIOS dispatcher).
	mov   r0, #0x4000000
	add   lr, pc, #0
	ldr   pc, [r0, #-4]          @ Load from 0x03FFFFFC (mirror of 0x03007FFC).

	@ Replicate BIOS IRQ dispatcher exit.
	ldmia sp!, {r0-r3, r12, lr}
	subs  pc, lr, #4

.pool
.global _gba_cheat_irq_handler_size
_gba_cheat_irq_handler_size = . - _gba_cheat_irq_handler
END_ASM_FUNC
