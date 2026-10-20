#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Optional patch: make the idle job workers of an Uncharted executable sleep instead of spinning.

    spin_backoff.py eboot.elf --out spin.bin [--after N] [--sleep-us M]

The collection's job system (the `NdJobWorker` threads) polls its work queues in a loop that, with the
flag at [rdi+0x59] clear, executes `pause` and polls again forever. A profile showed about 57% of all the
CPU time in that loop (it is the game's own design: the PS4 gives the game dedicated cores); on a laptop it
only burns power and heat. The patch keeps the spinning for the first N polls without work (r8 counts them,
so the game reacts at once when work arrives) and after that sleeps M microseconds per poll (nanosleep).

The loop is found by its bytes, not by an address, so it works for eboot.bin (Uncharted 1), big2 and big3:

    80 7f 59 00 74 d1  49 81 f8 e8 03 00 00  7c d2     cmp byte [rdi+0x59],0 ; je A1 ; cmp r8,0x3e8 ; jl A2
    A1/A2:  f3 90 e9 rel32                              pause ; jmp D           (the same D for both)

Both `jmp D` are redirected to a small routine placed in the block of zero padding that ends each of these
executables' text segment (it is never executed: the code before it ends in a function);
only the `jmp rel32` bytes (5 each) are rewritten, never the `pause`, so a thread can be anywhere in the loop
when the patch is applied. Nothing is written unless every byte matches; otherwise no file is produced and
the game starts unpatched. The output is a BBPATCH2 file for bb-probe's --patches; run.py applies it only
with BB_SPIN_BACKOFF=1 (BB_SPIN_AFTER and BB_SPIN_SLEEP_US set the two numbers).
"""
import argparse
import re
import struct
import sys
from pathlib import Path

EBOOT_BASE = 0x400000
SIGNATURE = re.compile(rb'\x80\x7f\x59\x00\x74(.)\x49\x81\xf8\xe8\x03\x00\x00\x7c(.)', re.S)
# The routine (87 bytes, position independent). Fields: cmp r8,imm32 @3; sleep ns imm32 @0x27; jmp D @0x4b and @0x52.
ROUTINE = bytes.fromhex(
    '4981f8b80b00007247488d642480505152565741539c4883ec1048c704240000000048c7442408307500004889e731f6b8'
    '230000000f054883c4109d415b5f5e5a5958488da42480000000e980d0b3fff390e979d0b3ff')
CAVE_SIZE = len(ROUTINE)  # 87
TAIL_ZEROS = 256           # the padding block must be at least this long, and end within TAIL_SLACK of the segment end
TAIL_SLACK = 0x100
CAVE_SKIP = 64             # keep this many zero bytes before the routine


def segments(elf):
    """Executable PT_LOAD segments: (file offset, vaddr, file size)."""
    phoff, = struct.unpack_from('<Q', elf, 0x20)
    phentsize, phnum = struct.unpack_from('<HH', elf, 0x36)
    found = []
    for i in range(phnum):
        kind, flags, offset, vaddr, _, filesz, _, _ = struct.unpack_from('<IIQQQQQQ', elf, phoff + i * phentsize)
        if kind == 1 and flags & 1:
            found.append((offset, vaddr, filesz))
    return found


def to_vaddr(segs, offset):
    for start, vaddr, size in segs:
        if start <= offset < start + size:
            return vaddr + offset - start
    return None


def to_offset(segs, vaddr):
    for start, base, size in segs:
        if base <= vaddr < base + size:
            return start + vaddr - base
    return None


def jmp_target(elf, segs, vaddr):
    """Destination of the `jmp rel32` at vaddr, or None when it is not one."""
    offset = to_offset(segs, vaddr)
    if offset is None or elf[offset] != 0xE9:
        return None
    rel, = struct.unpack_from('<i', elf, offset + 1)
    return vaddr + 5 + rel


def find_cave(elf, segs):
    """vaddr (16-byte aligned) of CAVE_SIZE bytes inside the zero padding at the end of the text, or None."""
    best = None
    for start, vaddr, size in segs:
        text = elf[start:start + size]
        for run in re.finditer(b'\x00{%d,}' % TAIL_ZEROS, text):
            if run.end() < size - TAIL_SLACK:
                continue                                  # not at the end of the segment: could be data
            first = (vaddr + run.start() + CAVE_SKIP + 15) & ~15
            if first + CAVE_SIZE <= vaddr + run.end() and (best is None or run.end() - run.start() > best[0]):
                best = (run.end() - run.start(), first)
    return best[1] if best else None


def build(elf, after, sleep_us):
    """[(vaddr, bytes)] writes, or (None, reason)."""
    segs = segments(elf)
    if not segs:
        return None, 'no executable segment'
    matches = list(SIGNATURE.finditer(elf))
    if len(matches) != 1:
        return None, f'the worker loop was found {len(matches)} times (expected 1): this is not a known executable'
    m = matches[0]
    base = to_vaddr(segs, m.start())
    if base is None:
        return None, 'the worker loop is outside the executable segments'
    je_rel, jl_rel = m.group(1)[0], m.group(2)[0]
    spin1 = base + 6 + je_rel            # je  (at base+4, 2 bytes) -> pause #1
    spin2 = base + 15 + jl_rel           # jl  (at base+13, 2 bytes) -> pause #2
    sites = []
    for spin in (spin1, spin2):
        offset = to_offset(segs, spin)
        if offset is None or elf[offset:offset + 2] != b'\xf3\x90':
            return None, f'no pause at 0x{spin:x}'
        sites.append(spin + 2)           # the `jmp rel32` after the pause
    targets = {jmp_target(elf, segs, s) for s in sites}
    if len(targets) != 1 or None in targets:
        return None, 'the two loop jumps do not go to the same place'
    target = targets.pop()
    cave = find_cave(elf, segs)
    if cave is None:
        return None, 'no zero padding at the end of the text large enough for the routine'
    routine = bytearray(ROUTINE)
    routine[3:7] = struct.pack('<I', after)
    routine[0x27:0x2B] = struct.pack('<I', sleep_us * 1000)
    routine[0x4C:0x50] = struct.pack('<i', target - (cave + 0x50))
    routine[0x53:0x57] = struct.pack('<i', target - (cave + 0x57))
    writes = [(cave, bytes(routine))]
    for site in sites:
        writes.append((site, b'\xe9' + struct.pack('<i', cave - (site + 5))))
    return writes, f'loop at 0x{base:x}, sites 0x{sites[0]:x} and 0x{sites[1]:x}, routine at 0x{cave:x}, jump to 0x{target:x}'


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('elf', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--after', type=int, default=300, help='polls without work before the first sleep')
    parser.add_argument('--sleep-us', type=int, default=50, help='microseconds slept per poll afterwards')
    args = parser.parse_args()
    args.out.unlink(missing_ok=True)
    if not (1 <= args.after <= 1_000_000 and 1 <= args.sleep_us <= 5000):
        print('Spin backoff: values out of range, not applied')
        return 0
    writes, info = build(args.elf.read_bytes(), args.after, args.sleep_us)
    if writes is None:
        print(f'Spin backoff: not applied ({info})')
        return 0
    blob = struct.pack('<8sQQ', b'BBPATCH2', EBOOT_BASE, len(writes))
    for vaddr, data in writes:
        blob += struct.pack('<QQ', vaddr, len(data)) + data
    args.out.write_bytes(blob)
    print(f'Spin backoff: idle workers spin {args.after} polls, then sleep {args.sleep_us} us ({info})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
