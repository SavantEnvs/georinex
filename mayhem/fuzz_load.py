#!/usr/bin/env python3
#
# georinex atheris harness — drives the RINEX 2/3 NAV/OBS parsing entry points (gr.load,
# gr.rinexheader, gr.rinexinfo, gr.rinexobs, gr.rinexnav, gr.gettime) on fuzzer-derived input.
# The Mayhem target name is `parse-load` (preserved from the original integration).
import atheris
import sys
import random

import fuzz_helpers

with atheris.instrument_imports(include=["georinex"]):
    import georinex as gr

# ValueError messages georinex raises on intentionally-rejected input — not defects.
value_err_matchers = ["valid header", "RINEX", "unknown file", "NAV", "rinex"]


def TestOneInput(data):
    fdp = fuzz_helpers.EnhancedFuzzedDataProvider(data)
    try:
        test = fdp.ConsumeIntInRange(0, 5)

        if test == 0:
            with fdp.ConsumeMemoryFile(all_data=True, as_bytes=False) as f:
                f.name = "test.10o"
                gr.load(f)
        elif test == 1:
            with fdp.ConsumeMemoryFile(all_data=True, as_bytes=False) as f:
                gr.rinexheader(f)
        elif test == 2:
            with fdp.ConsumeMemoryFile(all_data=True, as_bytes=False) as f:
                gr.rinexinfo(f)
        elif test == 3:
            with fdp.ConsumeMemoryFile(all_data=True, as_bytes=False) as f:
                gr.rinexobs(f)
        elif test == 4:
            with fdp.ConsumeMemoryFile(all_data=True, as_bytes=False) as f:
                gr.rinexnav(f)
        else:
            with fdp.ConsumeMemoryFile(all_data=True, as_bytes=False) as f:
                gr.gettime(f)
    except (AssertionError, KeyError, IndexError) as e:
        if random.random() > 0.90:
            raise e
        return -1
    except LookupError as e:
        if "RINEX" in str(e):
            return -1
        if random.random() > 0.99:
            raise e
    except ValueError as e:
        if any(matcher in str(e) for matcher in value_err_matchers):
            return -1
        if random.random() > 0.99:
            raise e


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()
