/*
 * pylauncher.c — minimal ELF libFuzzer launcher for an atheris (Python) harness.
 *
 * Mayhem requires the fuzz target to be a native ELF binary; an atheris harness is a `.py`
 * script. This launcher exec()s the Python interpreter on the baked-in harness script and
 * forwards ALL libFuzzer argv (-runs, -max_total_time, the corpus dir, -artifact_prefix, …)
 * unchanged, so atheris's embedded libFuzzer driver iterates exactly as it would natively.
 *
 * PYTHON and SCRIPT are pinned at compile time (-DPYTHON=… -DSCRIPT=…) by build.sh.
 */
#include <unistd.h>
#include <stdlib.h>

#ifndef PYTHON
#define PYTHON "/usr/bin/python3"
#endif
#ifndef SCRIPT
#define SCRIPT "/mayhem/mayhem/fuzz_load.py"
#endif

int main(int argc, char **argv) {
    /* argv -> { python, script, <original args...>, NULL } */
    char **a = (char **)malloc(sizeof(char *) * (argc + 2));
    if (!a) return 127;
    a[0] = (char *)PYTHON;
    a[1] = (char *)SCRIPT;
    for (int i = 1; i < argc; i++) a[i + 1] = argv[i];
    a[argc + 1] = NULL;
    execv(PYTHON, a);
    return 127; /* exec failed */
}
