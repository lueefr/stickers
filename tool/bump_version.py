#!/usr/bin/env python3
"""Compute the next app version for the Stickers release workflow.

Version scheme: single-digit minor/patch with rollover at 9, and a build
number after '+' that always increments by one:

  1.5.1 -> 1.5.2 -> ... -> 1.5.9 -> 1.6.0 -> ... -> 1.9.9 -> 2.0.0

The workflow takes the newest of pubspec.yaml and the latest GitHub Release
as the base, advances it with this script, writes it back to pubspec.yaml,
and publishes a `v<version>` release. A manual bump committed to pubspec.yaml
is therefore respected, and a stale pubspec.yaml self-heals from releases.

Usage:
  python3 tool/bump_version.py --pubspec
  python3 tool/bump_version.py --set-pubspec 1.5.2+20
  python3 tool/bump_version.py --check v1.5.1+19
  python3 tool/bump_version.py --next 1.5.1+19 [--bump patch|minor|major]
  python3 tool/bump_version.py --max 1.5.1+19 v1.6.0+20
  python3 tool/bump_version.py --plan --base 1.5.1+19 [--bump auto|patch|minor|major]
                               [--explicit 2.0.0]
"""

import argparse
import re
import sys
from pathlib import Path

VERSION_RE = re.compile(r"^[vV]?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$")
PUBSPEC_RE = re.compile(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s*$", re.MULTILINE)


def parse(value):
    """Parse '1.5.1+19' (or 'v1.5.1+19', '1.5.1') into (major, minor, patch, build)."""
    match = VERSION_RE.match(value.strip())
    if not match:
        raise ValueError(f"not a version like 1.5.1+19: {value!r}")
    major, minor, patch, build = match.groups()
    return (int(major), int(minor), int(patch), int(build or 0))


def fmt(version):
    major, minor, patch, build = version
    return f"{major}.{minor}.{patch}+{build}"


def next_version(base, bump="patch"):
    """Advance `base` one step; the build number always increments by one."""
    major, minor, patch, build = base
    build += 1
    if bump == "major":
        return (major + 1, 0, 0, build)
    if bump == "minor":
        if minor < 9:
            return (major, minor + 1, 0, build)
        return (major + 1, 0, 0, build)
    if bump != "patch":
        raise ValueError(f"unknown bump {bump!r}; expected patch, minor or major")
    # patch (also used by "auto"): roll over at 9 into the next minor,
    # and at 1.9.9 into the next major.
    if patch < 9:
        return (major, minor, patch + 1, build)
    if minor < 9:
        return (major, minor + 1, 0, build)
    return (major + 1, 0, 0, build)


def plan(base, bump="auto", explicit=None):
    """Compute the next version from `base`, honoring an explicit override."""
    if explicit:
        parsed = parse(explicit)
        # A bare name such as '2.0.0' keeps the normal build-number sequence;
        # an explicit '+N' is honored as given.
        build = parsed[3] if "+" in explicit else base[3] + 1
        result = (parsed[0], parsed[1], parsed[2], build)
        if result <= base:
            raise ValueError(
                f"explicit version {fmt(result)} is not newer than the base {fmt(base)}"
            )
        return result
    return next_version(base, "patch" if bump == "auto" else bump)


def read_pubspec(path="pubspec.yaml"):
    text = Path(path).read_text(encoding="utf-8")
    match = PUBSPEC_RE.search(text)
    if not match:
        raise ValueError(f"{path} must contain a numeric version such as 1.5.1+19")
    return match.group(1)


def write_pubspec(full_version, path="pubspec.yaml"):
    parse(full_version)  # validate before touching the file
    if "+" not in full_version:
        raise ValueError(f"pubspec version needs a build number: {full_version!r}")
    location = Path(path)
    text = location.read_text(encoding="utf-8")
    updated, count = PUBSPEC_RE.subn(f"version: {full_version}", text, count=1)
    if not count:
        raise ValueError(f"{path} must contain a numeric version such as 1.5.1+19")
    location.write_text(updated, encoding="utf-8")


def main(argv):
    parser = argparse.ArgumentParser(description="Compute the next Stickers app version.")
    parser.add_argument("--pubspec", action="store_true", help="print the pubspec.yaml version")
    parser.add_argument("--set-pubspec", metavar="FULL", help="rewrite the pubspec.yaml version")
    parser.add_argument("--file", metavar="PATH", default="pubspec.yaml",
                        help="pubspec file for --pubspec/--set-pubspec")
    parser.add_argument("--check", metavar="V", help="exit 0 when V parses, 1 otherwise")
    parser.add_argument("--next", metavar="BASE", help="print the version after BASE")
    parser.add_argument("--max", nargs=2, metavar=("A", "B"), help="print the newer of A and B")
    parser.add_argument("--plan", action="store_true", help="plan the next version from --base")
    parser.add_argument("--base", metavar="V", help="base version for --plan")
    parser.add_argument("--bump", default="auto", help="auto, patch, minor or major")
    parser.add_argument("--explicit", metavar="V", help="explicit version for --plan")
    args = parser.parse_args(argv)

    try:
        if args.pubspec:
            print(read_pubspec(args.file))
        elif args.set_pubspec:
            write_pubspec(args.set_pubspec, args.file)
            print(f"{args.file} is now {args.set_pubspec}")
        elif args.check is not None:
            try:
                parse(args.check)
            except ValueError:
                return 1
            return 0
        elif args.next is not None:
            bump = "patch" if args.bump == "auto" else args.bump
            print(fmt(next_version(parse(args.next), bump)))
        elif args.max is not None:
            print(fmt(max(parse(args.max[0]), parse(args.max[1]))))
        elif args.plan:
            if args.base is None:
                parser.error("--plan requires --base")
            print(fmt(plan(parse(args.base), args.bump, args.explicit)))
        else:
            parser.error("expected one of --pubspec, --set-pubspec, --check, --next, --max, --plan")
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
