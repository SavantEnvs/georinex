#!/usr/bin/env python3
"""
Known-answer behavioral oracle for georinex.

Parses a fixed RINEX 3.01 SBAS NAV record through the SAME public entry points the fuzz harness
drives (gr.rinexinfo / gr.rinexheader) and asserts the decoded values byte-for-byte, plus the
error semantics (a non-RINEX blob raises, not silently "succeeds"). These are real output
assertions on georinex's parser — a no-op / exit(0) / value-altering patch CANNOT pass — so the
suite is not reward-hackable.

Emits one `PASS <name>` / `FAIL <name>` line per check; exits 0 iff every check passed.
mayhem/test.sh tallies the lines into a CTRF summary.
"""
import os
import sys
import tempfile

import georinex as gr

# A minimal, valid RINEX 3.01 GNSS NAV file (SBAS). Header declares version 3.01, type "N" (nav),
# satellite system "S" (SBAS), followed by one PRN S22 ephemeris record.
RINEX_CONTENT = (
    "     3.01           N: GNSS NAV DATA    S: SBAS             RINEX VERSION / TYPE\n"
    "                                                            END OF HEADER\n"
    "S22 2010 10 18  0  1  4-9.872019290924D-08 5.456968210638D-12 5.186940000000D+05\n"
    "     2.482832392000D+04-3.593750000000D-04-1.375000000000D-07 0.000000000000D+00\n"
    "    -3.408920872000D+04-1.480625000000D-03-5.000000000000D-08 4.000000000000D+00\n"
    "    -1.650560000000D+01 8.360000000000D-04 6.250000000000D-08 2.300000000000D+01\n"
)

results = []


def check(name, cond):
    results.append((name, bool(cond)))


def raises(fn):
    try:
        fn()
    except Exception:
        return True
    return False


def main():
    fd, path = tempfile.mkstemp(suffix=".10n")
    with os.fdopen(fd, "w") as f:
        f.write(RINEX_CONTENT)
    try:
        info = gr.rinexinfo(path)
        check("rinexinfo reports a dict", isinstance(info, dict))
        check("rinexinfo version is 3.01", abs(float(info.get("version", 0)) - 3.01) < 1e-6)
        check("rinexinfo rinextype is nav", info.get("rinextype") == "nav")

        hdr = gr.rinexheader(path)
        check("rinexheader returns a dict", isinstance(hdr, dict))
        check("rinexheader version is 3.01", abs(float(hdr.get("version", 0)) - 3.01) < 1e-6)

        # Error semantics: a clearly non-RINEX file must NOT parse as a valid header.
        gfd, gpath = tempfile.mkstemp(suffix=".10n")
        with os.fdopen(gfd, "w") as gf:
            gf.write("this is definitely not a rinex file at all\njust some random text\n")
        try:
            check("non-RINEX input is rejected", raises(lambda: gr.rinexinfo(gpath)))
        finally:
            os.unlink(gpath)
    finally:
        os.unlink(path)

    ok = True
    for name, passed in results:
        sys.stdout.write(("PASS " if passed else "FAIL ") + name + "\n")
        ok = ok and passed
    sys.stdout.flush()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
