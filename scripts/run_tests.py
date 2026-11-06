#!/usr/bin/env python3
"""Discover and run every HDL example in the repository.

A *module directory* is any directory that contains an ``sv/`` or ``vhdl/``
subdirectory.  Layout (see CLAUDE.md for the full convention)::

    chNN_topic/example_name/
        README.md            textbook-style write-up
        deps.txt             optional: other module dirs (repo-relative) to compile first
        sv/*.sv              RTL + exactly one testbench file named tb_*.sv
        vhdl/*.vhd           RTL + exactly one testbench file named tb_*.vhd

Pass criterion: simulator exits 0, prints ``TEST PASSED`` and never prints
``TEST FAILED``.  SystemVerilog runs on Icarus Verilog (-g2012), VHDL on GHDL
(--std=08).  Optional ``--lint`` runs Verilator lint on the SV RTL.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
SKIP_DIRS = {".git", "build", "scripts", "docs", ".github"}


def find_modules() -> list[Path]:
    mods = []
    for p in sorted(ROOT.rglob("*")):
        if not p.is_dir() or any(part in SKIP_DIRS for part in p.relative_to(ROOT).parts):
            continue
        if (p / "sv").is_dir() or (p / "vhdl").is_dir():
            mods.append(p)
    return mods


def rel(p: Path) -> str:
    return str(p.relative_to(ROOT))


def sources(mod: Path, lang: str, include_tb: bool, seen: set[Path] | None = None) -> list[Path]:
    """RTL sources for `mod` (dependencies first); optionally the testbench last."""
    seen = seen if seen is not None else set()
    if mod in seen:
        return []
    seen.add(mod)
    out: list[Path] = []
    deps = mod / "deps.txt"
    if deps.exists():
        for line in deps.read_text().splitlines():
            line = line.split("#")[0].strip()
            if line:
                out += sources(ROOT / line, lang, False, seen)
    ext = "*.sv" if lang == "sv" else "*.vhd"
    files = sorted((mod / lang).glob(ext)) if (mod / lang).is_dir() else []
    rtl = [f for f in files if not f.name.startswith("tb_")]
    rtl.sort(key=lambda f: (not f.stem.endswith("_pkg"), f.name))  # packages first
    out += rtl
    if include_tb:
        out += [f for f in files if f.name.startswith("tb_")]
    return out


def run(cmd: list[str], cwd: Path, log: list[str]) -> tuple[int, str]:
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    out = r.stdout + r.stderr
    log.append("$ " + " ".join(cmd) + "\n" + out)
    return r.returncode, out


def judge(rc: int, out: str) -> bool:
    return rc == 0 and "TEST PASSED" in out and "TEST FAILED" not in out


def test_sv(mod: Path, log: list[str]) -> tuple[bool, str]:
    files = sources(mod, "sv", True)
    tbs = [f for f in files if f.name.startswith("tb_")]
    if len(tbs) != 1:
        return False, f"expected exactly one tb_*.sv, found {len(tbs)}"
    b = BUILD / rel(mod) / "sv"
    b.mkdir(parents=True, exist_ok=True)
    vvp = b / "sim.vvp"
    rc, out = run(["iverilog", "-g2012", "-Wall", "-Wno-timescale", "-s", tbs[0].stem,
                   "-o", str(vvp), *map(str, files)], b, log)
    if rc != 0:
        return False, "iverilog compile error"
    rc, out = run(["vvp", "-n", str(vvp)], b, log)
    return judge(rc, out), "" if judge(rc, out) else "simulation failed"


def test_vhdl(mod: Path, log: list[str]) -> tuple[bool, str]:
    files = sources(mod, "vhdl", True)
    tbs = [f for f in files if f.name.startswith("tb_")]
    if len(tbs) != 1:
        return False, f"expected exactly one tb_*.vhd, found {len(tbs)}"
    b = BUILD / rel(mod) / "vhdl"
    shutil.rmtree(b, ignore_errors=True)
    b.mkdir(parents=True)
    common = ["--std=08", f"--workdir={b}"]
    rc, out = run(["ghdl", "-a", *common, *map(str, files)], b, log)
    if rc != 0:
        return False, "ghdl analyse error"
    rc, out = run(["ghdl", "-e", *common, tbs[0].stem], b, log)
    if rc != 0:
        return False, "ghdl elaborate error"
    rc, out = run(["ghdl", "-r", *common, tbs[0].stem, "--assert-level=error"], b, log)
    return judge(rc, out), "" if judge(rc, out) else "simulation failed"


def lint_sv(mod: Path, log: list[str]) -> tuple[bool, str]:
    rtl = sources(mod, "sv", False)
    if not rtl:
        return True, "no sv"
    top = rtl[-1].stem
    rc, out = run(["verilator", "--lint-only", "-Wall", "-Wno-DECLFILENAME", "-Wno-UNUSEDSIGNAL",
                   "-Wno-UNUSEDPARAM", "-Wno-PINCONNECTEMPTY", "--top-module", top, *map(str, rtl)],
                  ROOT, log)
    return rc == 0, "" if rc == 0 else "verilator lint warnings/errors"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("filters", nargs="*", help="substring filters on module path (OR-ed)")
    ap.add_argument("--lang", choices=["sv", "vhdl", "all"], default="all")
    ap.add_argument("--list", action="store_true", help="list modules and exit")
    ap.add_argument("--lint", action="store_true", help="run Verilator lint instead of simulating")
    ap.add_argument("-v", "--verbose", action="store_true", help="print full tool output")
    args = ap.parse_args()

    mods = [m for m in find_modules() if not args.filters or any(f in rel(m) for f in args.filters)]
    if args.list:
        for m in mods:
            langs = [l for l in ("sv", "vhdl") if (m / l).is_dir()]
            print(f"{rel(m):55s} {','.join(langs)}")
        return 0
    if not mods:
        print("no modules matched", file=sys.stderr)
        return 2

    langs = ["sv", "vhdl"] if args.lang == "all" else [args.lang]
    fails, total = [], 0
    for m in mods:
        for lang in langs:
            if not (m / lang).is_dir():
                continue
            log: list[str] = []
            if args.lint:
                if lang != "sv":
                    continue
                ok, why = lint_sv(m, log)
            else:
                ok, why = (test_sv if lang == "sv" else test_vhdl)(m, log)
            total += 1
            print(f"{'PASS' if ok else 'FAIL'}  {lang:4s} {rel(m)}" + (f"   ({why})" if why else ""))
            if args.verbose or not ok:
                print("\n".join(log))
            if not ok:
                fails.append(f"{lang} {rel(m)}")
    print(f"\n{total - len(fails)}/{total} passed")
    for f in fails:
        print("  FAILED:", f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
