#!/usr/bin/env python3
"""Check the Android build config against the versions the Flutter tool enforces.

The regexes and the error/warn thresholds are taken from the Flutter SDK, so this
fails loudly if the project drifts back below a floor:

  * packages/flutter_tools/lib/src/android/gradle_utils.dart
      - gradleOrgVersionMatch, _androidGradlePluginRegExpFromId,
        _kotlinGradlePluginRegExpFromId
  * packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt
      - errorGradleVersion / warnGradleVersion
      - errorAGPVersion    / warnAGPVersion
      - errorKGPVersion    / warnKGPVersion

Usage: python3 tool/check_android_versions.py [android-dir]
"""

import configparser
import re
import sys
from pathlib import Path

# --- DependencyVersionChecker.kt thresholds -----------------------------------
ERROR_GRADLE = (8, 14, 0)
WARN_GRADLE = (9, 1, 0)
ERROR_AGP = (8, 11, 1)
WARN_AGP = (9, 0, 1)
ERROR_KGP = (2, 2, 20)
WARN_KGP = (2, 3, 20)

# --- gradle_utils.dart regexes (Python re has no \k, so quotes are spelled out) -
GRADLE_URL_RE = re.compile(
    r"^\s*distributionUrl\s*=\s*https\\://services\.gradle\.org/distributions/gradle-([\d.]+)-(.*)\.zip",
    re.MULTILINE,
)
AGP_RE = re.compile(
    r"""(?m)^\s*id\s*\(?\s*(?:"com\.android\.application"|'com\.android\.application')\s*\)?\s+version\s+"""
    r"""(?:"(?P<dv>[\d.]+)"|'(?P<sv>[\d.]+)')""",
)
KGP_RE = re.compile(
    r"""(?m)^\s*id\s*\(?\s*(?:"org\.jetbrains\.kotlin\.android"|'org\.jetbrains\.kotlin\.android')\s*\)?\s+version\s+"""
    r"""(?:"(?P<dv>[\d.]+)"|'(?P<sv>[\d.]+)')""",
)


def v(s):
    return tuple(int(p) for p in s.split(".") if p.isdigit())


def fmt(t):
    return ".".join(str(p) for p in t)


def check(name, have, error, warn):
    """Mirror DependencyVersionChecker: error below `error`, warn below `warn`."""
    if have < error:
        return ("FAIL", f"FAIL {name} {fmt(have)} is below the required {fmt(error)}")
    if warn and have < warn:
        return ("warn", f"warn {name} {fmt(have)} builds, but Flutter asks for {fmt(warn)}+ (non-fatal)")
    return ("ok", f"ok   {name} {fmt(have)}")


def main():
    android_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "android")
    failures = 0

    # Gradle: parse the properties file the way java.util.Properties does, then
    # match it with Flutter's own gradleOrgVersionMatch regex.
    props_file = android_dir / "gradle" / "wrapper" / "gradle-wrapper.properties"
    cp = configparser.ConfigParser(strict=False, interpolation=None)
    cp.read_string("[d]\n" + props_file.read_text())
    cp["d"]["distributionUrl"]  # raises if the key is missing
    text = props_file.read_text()
    match = GRADLE_URL_RE.search(text)
    if not match:
        print(f"FAIL {props_file}: distributionUrl does not match Flutter's gradleOrgVersionMatch")
        return 1
    print(f"     distributionUrl resolves to gradle-{match.group(1)}-{match.group(2)}.zip")

    settings = (android_dir / "settings.gradle").read_text()
    agp_match = AGP_RE.search(settings)
    kgp_match = KGP_RE.search(settings)
    if not agp_match or not kgp_match:
        print("FAIL android/settings.gradle: could not find the AGP / KGP plugin versions")
        return 1

    results = [
        check("Gradle", v(match.group(1)), ERROR_GRADLE, WARN_GRADLE),
        check("AGP   ", v(agp_match.group("dv") or agp_match.group("sv")), ERROR_AGP, WARN_AGP),
        check("KGP   ", v(kgp_match.group("dv") or kgp_match.group("sv")), ERROR_KGP, WARN_KGP),
    ]
    for _, line in results:
        print(line)
        if _ == "FAIL":
            failures += 1

    # key.properties is gitignored, so release signing has to be conditional or a
    # fresh clone fails during configuration.
    app_gradle = (android_dir / "app" / "build.gradle").read_text()
    signing_block = app_gradle[app_gradle.index("signingConfigs {"):]
    signing_block = signing_block[: signing_block.index("buildTypes {")]
    if 'create("release")' in signing_block and "keystorePropertiesFile.exists()" not in signing_block:
        print('FAIL android/app/build.gradle: the "release" signing config is created '
              "unconditionally but key.properties is gitignored")
        failures += 1
    else:
        print("ok   release signing is guarded by key.properties existing")

    print(f"\n{failures} problem(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
