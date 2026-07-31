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
if [[ $dsm -ge 7 ]]; then
    VAR_DIR="${PKG_ROOT}/var"
else
    VAR_DIR="${PKG_ROOT}/etc"
fi

SCRIPT="${BIN_DIR}/syno_cpu_temp.sh"
CONF_FILE="${VAR_DIR}/syno_cpu_temp.conf"
LOG_FILE="${VAR_DIR}/syno_cpu_temp.log"
DEFAULT_LOG_DAYS=7

if [[ ! -f "$CONF_FILE" ]]; then
    touch "$CONF_FILE"
    synosetkeyvalue "$CONF_FILE" Log ""
    synosetkeyvalue "$CONF_FILE" Log_Days 7
    synosetkeyvalue "$CONF_FILE" Log_Repeat_Hour "1"
fi

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
    [ -n "$days" ] || days="$DEFAULT_LOG_DAYS"

    python3 -c "
import re
from datetime import datetime, timedelta

log_file = '${LOG_FILE}'
days = int('${days}')
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

getsettings)
    LOG_ENABLED=$(synogetkeyvalue "$CONF_FILE" Log 2>/dev/null)
    LOG_DAYS=$(synogetkeyvalue "$CONF_FILE" Log_Days 2>/dev/null)
    LOG_REPEAT_HOUR=$(synogetkeyvalue "$CONF_FILE" Log_Repeat_Hour 2>/dev/null)
    [ -n "$LOG_DAYS" ] || LOG_DAYS="$DEFAULT_LOG_DAYS"
    [ -n "$LOG_REPEAT_HOUR" ] || LOG_REPEAT_HOUR="1"
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
        "$TASK_SETUP" set "$FREQUENCY" >>"${VAR_DIR}/api.log" 2>&1
    else
        "$TASK_SETUP" disable >>"${VAR_DIR}/api.log" 2>&1
    fi

    echo '{"success":true}'
    ;;

*)
    echo '{"success":false,"message":"Unknown action"}'
    exit 1
    ;;
esac
