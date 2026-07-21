#!/usr/bin/env python3
"""Dump USB/ATC/Type-C ADT metadata without reading or writing MMIO.

Unlike m1n1.setup, this deliberately does not instantiate the PMU helper or
reset its panic counter. It reads the already-captured ADT directly from the
boot-args memory image and never calls p.read*/p.write* on device registers.
"""

import argparse
import hashlib
import os
from pathlib import Path

from m1n1 import adt
from m1n1.proxy import M1N1Proxy, UartInterface
from m1n1.tgtypes import BootArgs_r1, BootArgs_r2, BootArgs_r3


TERMS = ("usb", "atc", "typec", "type-c", "hpm", "cd321", "thunderbolt")


def relevant(node):
    names = [node._path, *node._properties.keys(), *node._properties.values()]
    return any(term in str(name).lower() for name in names for term in TERMS)


def dump_node(node):
    print(f"NODE {node._path}")
    for name, value in node._properties.items():
        if name == "name":
            continue
        try:
            value = node._fmt_prop(name, value)
        except Exception:
            value = repr(value)
        print(f"  {name} = {value}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--raw-output",
        type=Path,
        required=True,
        help="new host-side path for the complete authoritative ADT capture",
    )
    args = parser.parse_args()

    device = os.environ.get("M1N1DEVICE")
    if device != "/tmp/m1n1":
        parser.error("M1N1DEVICE must be /tmp/m1n1 (KIS); UART is refused")
    iface = UartInterface(device=device)
    iface.nop()
    proxy = M1N1Proxy(iface, debug=False)

    bootargs_addr, bootargs_rev = proxy.get_bootargs_rev()
    if bootargs_rev <= 1:
        bootargs_type = BootArgs_r1
    elif bootargs_rev == 2:
        bootargs_type = BootArgs_r2
    elif bootargs_rev == 3:
        bootargs_type = BootArgs_r3
    else:
        raise RuntimeError(f"unsupported boot-args revision {bootargs_rev}")
    bootargs = iface.readstruct(bootargs_addr, bootargs_type)
    adt_addr = (
        bootargs.devtree - bootargs.virt_base + bootargs.phys_base
    ) & 0xFFFFFFFFFFFFFFFF
    adt_data = iface.readmem(adt_addr, bootargs.devtree_size)

    try:
        output_fd = os.open(
            args.raw_output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600
        )
    except FileExistsError:
        parser.error(f"refusing to overwrite existing capture: {args.raw_output}")
    with os.fdopen(output_fd, "wb") as output:
        output.write(adt_data)
    digest = hashlib.sha256(adt_data).hexdigest()
    print(f"RAW_ADT {args.raw_output} {len(adt_data)} bytes sha256={digest}")
    print()

    tree = adt.load_adt(adt_data)

    matches = []
    for root_path in ("/arm-io", "/chosen"):
        root = tree[root_path]
        matches.extend(node for node in root.walk_tree() if relevant(node))

    for index, node in enumerate(matches):
        if index:
            print()
        dump_node(node)


if __name__ == "__main__":
    main()
