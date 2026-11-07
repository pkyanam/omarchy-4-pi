#!/usr/bin/python3
"""Resolve the Pi package contract using signed repositories and pacman's solver.

Database parsing supports versioned Provides; pacman still validates dependency
closure, conflicts and package signatures. This helper never installs anything.
"""

import argparse
import re
import subprocess
import sys
import tarfile
from pathlib import Path

DEPENDENCY = re.compile(r"^([a-zA-Z0-9@._+:-]+)(?:(>=|<=|=|>|<)([^\s]+))?$")
REPOS = ("omarchy", "core", "extra", "alarm")
PROTECTED = {"omarchy", "omarchy-settings", "omarchy-dev", "omarchy-settings-dev"}


def dependency(value):
    match = DEPENDENCY.fullmatch(value)
    if not match:
        raise ValueError(f"invalid dependency expression: {value}")
    return match.groups()


def satisfies(actual, operator, expected):
    if not operator:
        return True
    if not actual:
        return False  # Unversioned Provides cannot meet a version constraint.
    order = int(subprocess.check_output(["vercmp", actual, expected], text=True).strip())
    return {"=": order == 0, ">=": order >= 0, "<=": order <= 0,
            ">": order > 0, "<": order < 0}[operator]


def lines(path):
    for raw in path.read_text().splitlines():
        value = raw.split("#", 1)[0].strip()
        if value:
            yield value


def contract(root):
    excluded = set(lines(root / "install/omarchy-rpi4-unavailable.packages"))
    policy = {}
    for filename in ("omarchy-base.packages", "omarchy-aarch64.packages"):
        for request in lines(root / "install" / filename):
            name, _, _ = dependency(request)
            if name not in excluded:
                policy[name] = ("required", request)
    for row in lines(root / "install/omarchy-rpi4.packages"):
        words = row.split()
        if words[0] == "map":
            _, original, binary = words
            dependency(original)
            dependency(binary)
            if original not in policy or binary in excluded or binary in PROTECTED:
                raise ValueError(f"invalid Pi binary package mapping: {row}")
            role, _ = policy.pop(original)
            policy[binary] = (role, binary)
            continue
        role, request = words
        if role not in ("required", "optional"):
            raise ValueError(f"unknown Pi package role: {role}")
        name, _, _ = dependency(request)
        if name in excluded or name in PROTECTED:
            raise ValueError(f"conflicting Pi package policy: {name}")
        policy[name] = (role, request)
    return policy


def databases(dbpath):
    packages = []
    for repo in REPOS:
        with tarfile.open(dbpath / "sync" / f"{repo}.db") as archive:
            for member in archive:
                if not member.isfile() or not member.name.endswith("/desc"):
                    continue
                record = {}
                data = archive.extractfile(member).read().decode()
                for field in data.split("\n\n"):
                    parts = field.strip().splitlines()
                    if parts and parts[0].startswith("%"):
                        record[parts[0].strip("%")] = parts[1:]
                if not all(record.get(key) for key in ("NAME", "VERSION", "ARCH")):
                    # The stable ALARM extra database contains an old all-NUL
                    # findnewest record. Do not let an unrelated broken entry
                    # hide a usable contract; required unresolved requests still
                    # fail below, and pacman validates the actual transaction.
                    print(f"Pi repository warning: ignoring incomplete metadata {repo}/{member.name}", file=sys.stderr)
                    continue
                if record["ARCH"][0] not in ("any", "aarch64"):
                    raise ValueError(f"non-ARM package in {repo}: {record['NAME'][0]}")
                record["REPO"] = repo
                packages.append(record)
    return packages


def resolve(request, packages):
    name, operator, version = dependency(request)
    # Repository order wins over a later repository's literal package name.
    for repo in REPOS:
        candidates = [p for p in packages if p["REPO"] == repo]
        for record in candidates:
            if record["NAME"][0] == name and satisfies(record["VERSION"][0], operator, version):
                return record
        for record in candidates:
            for provided in record.get("PROVIDES", []):
                provided_name, _, provided_version = dependency(provided)
                if provided_name == name and satisfies(provided_version, operator, version):
                    return record
    raise ValueError(f"no stable ARM binary satisfies {request}")


def solver(targets):
    if not targets:
        return
    result = subprocess.run(["pacman", "-Sp", "--noconfirm", "--print-format", "%r/%n %v %a", "--", *targets],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError(result.stderr.strip() or "pacman could not resolve dependency closure")
    for row in result.stdout.splitlines():
        # stdout may contain pacman's provider headings. Package records have
        # precisely this print-format; every resulting package must be ARM.
        if "/" not in row or len(row.split()) != 3:
            continue
        target, _, arch = row.split()
        repo, name = target.split("/", 1)
        if repo not in REPOS or arch not in ("any", "aarch64") or name in PROTECTED:
            raise ValueError(f"unsafe dependency selected by pacman: {row}")


def plan(root, mode, packages):
    selected = {}
    optional = []
    failures = []
    for role, request in contract(root).values():
        if role == "optional" and mode == "minimal":
            print(f"Pi optional omission (--minimal): {request}", file=sys.stderr)
            continue
        try:
            record = resolve(request, packages)
        except ValueError as error:
            if role == "required":
                failures.append(str(error))
            else:
                print(f"Pi optional omission: {error}", file=sys.stderr)
            continue
        name = record["NAME"][0]
        if role == "optional":
            optional.append(record)
        else:
            selected[name] = record
    if failures:
        raise ValueError("unresolved required Pi runtime:\n  " + "\n  ".join(failures))
    solver([f"{p['REPO']}/{p['NAME'][0]}" for p in selected.values()])
    for record in optional:
        try:
            solver([f"{record['REPO']}/{record['NAME'][0]}"])
        except ValueError as error:
            print(f"Pi optional omission: {record['NAME'][0]}: {error}", file=sys.stderr)
        else:
            selected[record["NAME"][0]] = record
    solver([f"{p['REPO']}/{p['NAME'][0]}" for p in selected.values()])
    return list(selected.values())


def verify(selected, require_backports=False):
    for record in selected:
        name, expected = record["NAME"][0], record["VERSION"][0]
        acceptable = {expected}
        # Older installed updaters verify the full repository transaction
        # before calling the new checkout's runtime reconciliation. Permit
        # that intermediate base version, but require the fix at completion.
        if name == "bluez-utils" and expected == "5.87-2":
            acceptable = {"5.87-2.1"} if require_backports else {"5.87-2", "5.87-2.1"}
        result = subprocess.run(["pacman", "-Q", name], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        installed = result.stdout.split()
        if result.returncode or len(installed) != 2 or installed[1] not in acceptable:
            raise ValueError(f"Pi runtime {name} must be {' or '.join(sorted(acceptable))}; installed: {result.stdout.strip() or 'absent'}")


def install_targets(selected):
    for record in selected:
        name, version = record["NAME"][0], record["VERSION"][0]
        if name == "bluez-utils" and version == "5.87-2":
            installed = subprocess.run(["pacman", "-Q", name], text=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if installed.returncode == 0 and installed.stdout.split() == [name, "5.87-2.1"]:
                # An explicit -S target downgrades even with --needed. Keep
                # the backport out of both old and new updaters' targets;
                # it remains in the complete solver/verification contract.
                continue
        yield f"{record['REPO']}/{name}={version}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("mode", choices=("minimal", "full"))
    parser.add_argument("--dbpath", type=Path, default=Path("/var/lib/pacman"))
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--require-backports", action="store_true")
    args = parser.parse_args()
    selected = plan(args.root, args.mode, databases(args.dbpath))
    if args.verify:
        verify(selected, args.require_backports)
    for target in install_targets(selected):
        print(target)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, tarfile.TarError, subprocess.CalledProcessError) as error:
        sys.exit(f"Pi package contract failed: {error}")
