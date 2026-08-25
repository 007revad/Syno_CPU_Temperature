#!/bin/bash
#----------------------------------------------------------
# CPUTemp package - root-run wrapper, called via sudo from api.cgi.
#
# syno_cpu_temp.sh already reads Log/Log_Directory from
# syno_cpu_temp.conf next to it (via synogetkeyvalue), and writes the
# log header itself the first time it runs. This wrapper adds:
#   - a Log_Days key in the same conf file (new, package-specific)
#   - pruning of log entries older than Log_Days after each run
#   - settings read/write for the Settings window
#
# Usage:
#   cpu_temp_api.sh run
#   cpu_temp_api.sh getlog
#   cpu_temp_api.sh getsettings
#   cpu_temp_api.sh setsettings <log_enabled yes|no> <log_days N>
#----------------------------------------------------------

PKG_NAME="CPUTemp"
PKG_ROOT="/var/packages/${PKG_NAME}"
BIN_DIR="${PKG_ROOT}/target/bin"

# Get DSM major version
dsm=$(/usr/syno/bin/synogetkeyvalue /etc.defaults/VERSION majorversion)
if ! [[ "$dsm" =~ ^[0-9]+$ ]]; then
    echo '{"success":false,"message":"Unable to determine DSM version"}' >&2
    exit 1
fi
if [[ $dsm -ge 7 ]]; then
    VAR_DIR="${PKG_ROOT}/var"
else
    VAR_DIR="${PKG_ROOT}/etc"
fi

SCRIPT="${BIN_DIR}/syno_cpu_temp.sh"
CONF_FILE="${VAR_DIR}/syno_cpu_temp.conf"
LOG_FILE="${VAR_DIR}/syno_cpu_temp.log"
API_LOG_FILE="${VAR_DIR}/api.log"
DEFAULT_LOG_DAYS=7

if [[ ! -f "$CONF_FILE" ]]; then
    touch "$CONF_FILE"
    synosetkeyvalue "$CONF_FILE" Log ""
    synosetkeyvalue "$CONF_FILE" Log_Days 7
    synosetkeyvalue "$CONF_FILE" Log_Repeat_Hour "1"
fi

# ---------------------------------------------------------------------
# Self-heal file ownership.
#
# bin/ and bin/modules/ are locked to 555 by postinst, which blocks
# create/delete/rename of files inside them - but postinst runs as
# CPUTemp, not root (confirmed 2026-08-15), so it can never chown
# anything. Every file under bin/ therefore starts out still owned by
# CPUTemp. An owner can always chmod u+w their own file regardless
# of the containing directory's permissions, then overwrite its
# content in place - confirmed exploitable against conf_lib.sh on
# DS218 2026-08-15 despite bin/ being 555.
#
# Since this script always runs as root (invoked only via
# synocputemp-helper's setuid), it closes that gap on every single
# invocation: chown root:root + re-lock any file that's still
# CPUTemp-owned. Cheap enough to run unconditionally rather than
# caching a "did we already do this" flag - a handful of stat calls.
#
# Targets are found by globbing bin/ directly. Since both directories 
# are 555 (no new files can be created), globbing what's actually on 
# disk covers every possible overwrite target without trusting content
# that could be the attack itself.
#
# LIMITATION: This cannot protect this script (cpu_temp_api.sh)
# itself if it's been replaced before this code runs, the replacement
# executes instead and this check never fires - self-heal logic in the
# original file doesn't help once the original file is gone. This is
# a narrow, accepted gap: the window between postinst completing and
# the first invocation of this script (which happens automatically on
# first page load via getstate). Everything this function iterates
# over is fully self-healing from that point forward; this file itself
# is the one exception.
self_heal() {
    local f owner
    for f in "$BIN_DIR"/*.sh "$BIN_DIR"/*.py "$0"; do
        [[ -f "$f" ]] || continue
        owner="$(stat -c '%U' "$f" 2>/dev/null)"
        if [[ "$owner" != "root" ]]; then
            chown root:root "$f" 2>/dev/null
            chmod 555 "$f" 2>/dev/null
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] CPUTemp: self-heal secured $f (was owned by $owner)" \
                >> "${API_LOG_FILE}" 2>/dev/null
        fi
    done

    # syno_cpu_temp.conf is data, not code - root still writes it on every
    # save. 600 rather than 555: no group/other bits at all, since
    # root bypasses the mode entirely and the only thing left to
    # control is whether CPUTemp can read config values (some,
    # e.g. config_backup_remote_user/_remote_ip, are worth keeping
    # off a wider read path even though nothing currently depends on
    # that confidentiality).
    if [[ -f "$CONF_FILE" ]]; then
        owner="$(stat -c '%U' "$CONF_FILE" 2>/dev/null)"
        if [[ "$owner" != "root" ]]; then
            chown root:root "$CONF_FILE" 2>/dev/null
            chmod 600 "$CONF_FILE" 2>/dev/null
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] CPUTemp: self-heal secured $CONF_FILE (was owned by $owner)" \
                >> "${API_LOG_FILE}" 2>/dev/null
        fi
    fi

    # Remove leftover sudoers rule from the pre-setuid-helper design.
    # No longer independently exploitable once the scripts above are
    # root-owned 555 (a NOPASSWD entry pointing at a script the
    # invoking user can't write to isn't itself an escalation path),
    # but it's unnecessary attack surface left behind on an in-place
    # upgrade of an old install, and worth clearing rather than
    # leaving as an inert-but-present entry. Only root can delete
    # anything under /etc/sudoers.d/, so - same as the ownership
    # fixes above - this only works from here, whether invoked via
    # the helper (DSM7) or directly (DSM6).
    SUDOERS_FILE="/etc/sudoers.d/${PKG_NAME}"
    if [[ -f "$SUDOERS_FILE" ]]; then
        rm -f "$SUDOERS_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] CPUTemp: self-heal removed leftover sudoers file $SUDOERS_FILE" \
            >> "${API_LOG_FILE}" 2>/dev/null
    fi

    # Ensure api.log itself is CPUTemp-owned, not root-owned. If this
    # function's own writes above are what create api.log for the
    # first time (e.g. postinst's selfheal call on a fresh @appdata,
    # before api.cgi's own touch/chown ever runs), the file is created
    # as root:CPUTemp - and once that happens, api.cgi's unprivileged
    # chown can never fix it (EPERM: not the owner). Root can always
    # chown here, so fix it unconditionally rather than checking first.
    if [[ -f "$API_LOG_FILE" ]]; then
        chown "${PKG_NAME}:${PKG_NAME}" "$API_LOG_FILE" 2>/dev/null
        chmod 644 "$API_LOG_FILE" 2>/dev/null
    fi
}

self_heal

ACTION="$1"
shift

# Prune log entries older than Log_Days. Lines start with
# "YYYY-MM-DD HH:MM:SS - " (syno_cpu_temp.sh's $now format); header
# lines (script version, model, max temp, etc.) have no such prefix
# and are always kept.
prune_log() {
    [ -f "$LOG_FILE" ] || return 0

    local days
    days=$(synogetkeyvalue "$CONF_FILE" Log_Days 2>/dev/null)
    [[ "$days" =~ ^[0-9]+$ ]] || days="$DEFAULT_LOG_DAYS"

    LOG_FILE="$LOG_FILE" DAYS="$days" python3 -c "
import os, re
from datetime import datetime, timedelta

log_file = os.environ['LOG_FILE']
days = int(os.environ['DAYS'])
cutoff = datetime.now() - timedelta(days=days)
ts_re = re.compile(r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) - ')

with open(log_file) as f:
    lines = f.readlines()

kept = []
for line in lines:
    m = ts_re.match(line)
    if not m:
        kept.append(line)  # header line, always keep
        continue
    try:
        ts = datetime.strptime(m.group(1), '%Y-%m-%d %H:%M:%S')
    except ValueError:
        kept.append(line)
        continue
    if ts >= cutoff:
        kept.append(line)

with open(log_file, 'w') as f:
    f.writelines(kept)
" 2>>"${VAR_DIR}/api.log"
}

case "$ACTION" in
run)
    mkdir -p "$VAR_DIR"
    if [ ! -x "$SCRIPT" ]; then
        echo '{"success":false,"message":"syno_cpu_temp.sh missing or not executable"}'
        exit 1
    fi
    "$SCRIPT" >/dev/null 2>>"${VAR_DIR}/api.log"
    RC=$?
    if [ "$RC" -ne 0 ]; then
        echo "{\"success\":false,\"message\":\"syno_cpu_temp.sh exited with code ${RC}\"}"
        exit 0
    fi
    prune_log
    echo '{"success":true}'
    ;;

getlog)
    if [ -f "$LOG_FILE" ]; then
        python3 -c "
import json
with open('${LOG_FILE}') as f:
    print(json.dumps(f.read()))
"
    else
        echo '""'
    fi
    ;;

clearlog)
    # rm rather than truncate: syno_cpu_temp.sh only writes its header
    # block when the log file doesn't already exist, so a truncated
    # (but still present) empty file would skip the header on the
    # next run.
    rm -f "$LOG_FILE"
    echo '{"success":true}'
    ;;

getsettings)
    LOG_ENABLED=$(synogetkeyvalue "$CONF_FILE" Log 2>/dev/null)
    LOG_DAYS=$(synogetkeyvalue "$CONF_FILE" Log_Days 2>/dev/null)
    LOG_REPEAT_HOUR=$(synogetkeyvalue "$CONF_FILE" Log_Repeat_Hour 2>/dev/null)
    [ -n "$LOG_DAYS" ] || LOG_DAYS="$DEFAULT_LOG_DAYS"
    [ -n "$LOG_REPEAT_HOUR" ] || LOG_REPEAT_HOUR="1"

    # Reconcile against the actual scheduled task - conf file state can
    # drift if the task was deleted directly in DSM's Task Scheduler,
    # bypassing this package entirely.
    if [[ "${LOG_ENABLED,,}" == "yes" ]]; then
        TASK_CHECK=$("${BIN_DIR}/task_setup.sh" find 2>>"${VAR_DIR}/api.log")
        if ! echo "$TASK_CHECK" | grep -q '"exists":true'; then
            LOG_ENABLED="no"
            synosetkeyvalue "$CONF_FILE" Log "no"
            echo "CPUTemp: getsettings reconciled Log=no (scheduled task missing)" >> "${VAR_DIR}/api.log"
        fi
    fi

    if [[ "${LOG_ENABLED,,}" == "yes" ]]; then ENABLED_JSON=true; else ENABLED_JSON=false; fi
    echo "{\"success\":true,\"log_enabled\":${ENABLED_JSON},\"log_days\":${LOG_DAYS},\"frequency\":${LOG_REPEAT_HOUR}}"
    ;;

setsettings)
    LOG_ENABLED="$1"
    LOG_DAYS="$2"
    FREQUENCY="$3"

    if [[ "$LOG_ENABLED" != "yes" && "$LOG_ENABLED" != "no" ]]; then
        echo '{"success":false,"message":"log_enabled must be yes or no"}'
        exit 1
    fi
    if ! [[ "$LOG_DAYS" =~ ^[0-9]+$ ]] || [ "$LOG_DAYS" -lt 1 ]; then
        echo '{"success":false,"message":"log_days must be a positive number"}'
        exit 1
    fi

    synosetkeyvalue "$CONF_FILE" Log "$LOG_ENABLED"
    synosetkeyvalue "$CONF_FILE" Log_Days "$LOG_DAYS"
    synosetkeyvalue "$CONF_FILE" Log_Repeat_Hour "$FREQUENCY"

    prune_log

    TASK_SETUP="${BIN_DIR}/task_setup.sh"
    if [[ "$LOG_ENABLED" == "yes" && -n "$FREQUENCY" ]]; then
        TASK_OUTPUT=$("$TASK_SETUP" set "$FREQUENCY" 2>>"${VAR_DIR}/api.log")
    else
        TASK_OUTPUT=$("$TASK_SETUP" remove 2>>"${VAR_DIR}/api.log")
    fi
    echo "$TASK_OUTPUT" >> "${VAR_DIR}/api.log"

    if echo "$TASK_OUTPUT" | grep -q '"success":false'; then
        echo "$TASK_OUTPUT"
        exit 1
    fi

    echo '{"success":true}'
    ;;

removeschedule)
    TASK_OUTPUT=$("${BIN_DIR}/task_setup.sh" remove 2>>"${VAR_DIR}/api.log")
    echo "$TASK_OUTPUT" >> "${VAR_DIR}/api.log"
    if echo "$TASK_OUTPUT" | grep -q '"success":false'; then
        echo "$TASK_OUTPUT"
        exit 1
    fi
    echo '{"success":true}'
    ;;

    *)
    echo '{"success":false,"message":"Unknown action"}'
    exit 1
    ;;
esac
