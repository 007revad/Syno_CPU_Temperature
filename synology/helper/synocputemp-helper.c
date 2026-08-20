/*
 * synocputemp-helper.c
 *
 * Narrow setuid-root launcher for Syno_CPU Temperature.
 * Installed by DSM owner root:<package>, mode 6550 (setuid), from conf/privilege.
 *
 * This replaces the sudoers-based escalation: it does not depend on
 * /usr/bin/sudo being present, and only ever executes one fixed,
 * hardcoded script path with a whitelisted set of no-argument or
 * fixed-three-argument commands.
 */

#define _GNU_SOURCE
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#ifndef TARGET_SCRIPT
#define TARGET_SCRIPT "/var/packages/CPUTemp/target/bin/cpu_temp_api.sh"
#endif

int main(int argc, char *argv[])
{
    const char *no_arg[] = { "run", "getlog", "clearlog", "getsettings", "selfheal", "removeschedule", NULL };
    const char *three_arg[] = { "setsettings", NULL };

    if (argc < 2) {
        fprintf(stderr, "synocputemp-helper: missing subcommand\n");
        return 1;
    }
    const char *cmd = argv[1];

    int is_no_arg = 0, is_three_arg = 0;
    for (int i = 0; no_arg[i] != NULL; i++)
        if (strcmp(cmd, no_arg[i]) == 0) { is_no_arg = 1; break; }
    for (int i = 0; three_arg[i] != NULL; i++)
        if (strcmp(cmd, three_arg[i]) == 0) { is_three_arg = 1; break; }

    if ((is_no_arg && argc != 2) || (is_three_arg && argc != 5) ||
        (!is_no_arg && !is_three_arg)) {
        fprintf(stderr, "synocputemp-helper: rejected '%s' with %d argument(s)\n",
                cmd, argc - 2);
        return 1;
    }

    /* setuid binary gives us euid=0; promote ruid too so the exec'd
     * script is genuinely root, not just effectively root. */
    if (setuid(0) != 0) {
        perror("synocputemp-helper: setuid(0) failed");
        return 1;
    }

    /* Sanitize environment: fixed PATH, no inherited surprises. */
    if (clearenv() != 0) {
        fprintf(stderr, "synocputemp-helper: clearenv failed\n");
        return 1;
    }
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin:/usr/syno/bin:/usr/syno/sbin", 1);
    setenv("HOME", "/root", 1);

    if (argc == 2) {
        execl(TARGET_SCRIPT, TARGET_SCRIPT, cmd, (char *)NULL);
    } else if (argc == 5) {
        execl(TARGET_SCRIPT, TARGET_SCRIPT, cmd, argv[2], argv[3], argv[4], (char *)NULL);
    } else {
        execl(TARGET_SCRIPT, TARGET_SCRIPT, cmd, argv[2], (char *)NULL);
    }

    perror("synocputemp-helper: execl failed");
    return 1;
}