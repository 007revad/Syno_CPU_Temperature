#!/bin/bash
#----------------------------------------------------------
# Creates/updates/disables the CPUTemp scheduled task via
# SYNO.Core.TaskScheduler. Run as root (sudo'd from cpu_temp_api.sh).
#
# Confirmed 2026-07-31 against real test tasks:
#   DSM 7 (api version 4): schedule needs repeat_hour, repeat_min,
#     repeat_date=1001 (the "daily repeat" marker for v4 - a plain 0
#     was rejected with "Invalid repeat [0] for date_type [0] for v4"),
#     and a "version":4 key nested inside the schedule object itself.
#   DSM 6 (api version 1): schedule has no repeat_min/version keys;
#     repeat_date=0 is correct for daily repeat.
#   Both confirmed via method=create on DS218 (DSM7) and by reading
#   back a task manually created on Webber (DSM6) with synowebapi
#   method=get.
#
#   method=list always needs version=1 regardless of DSM major
#   version - unlike create/get, which use version=1 (DSM6) or
#   version=4 (DSM7). Confirmed 2026-07-31 on DS218 (DSM7): version=4
#   with list silently returned nothing usable.
#
# UNVERIFIED: method=set (for editing an existing task) is assumed to
# take the same param shape as method=create, plus "id". This has not
# been tested against a real DSM response yet - if editing a schedule
# ever behaves oddly, this is the first thing to check.
#
# Usage:
#   task_setup.sh set <repeat_hour 1-11>
#   task_setup.sh disable
#----------------------------------------------------------

PKG_NAME="CPUTemp"
PKG_DEST="/var/packages/${PKG_NAME}/target"
TASK_NAME="CPU Temperature"
COMMAND="${PKG_DEST}/bin/cpu_temp_api.sh run"

# Same DSM-major-version detection syno_cpu_temp.sh itself uses.
dsm=$(get_key_value /etc.defaults/VERSION majorversion)
if [[ $dsm -ge 7 ]]; then
    VAR_DIR="/var/packages/${PKG_NAME}/var"
    API_VER=4
else
    API_VER=1
    VAR_DIR="/var/packages/${PKG_NAME}/etc"
fi

find_task_id() {
    local raw
    raw=$(synowebapi -s --exec api=SYNO.Core.TaskScheduler method=list version=1 2>>"${VAR_DIR}/api.log")
    echo "$raw" >> "${VAR_DIR}/api.log"
    echo "$raw" | python3 -c "
import json, sys

raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception as e:
    sys.stderr.write('find_task_id: JSON parse failed: %s\n' % e)
    sys.exit(0)

tasks = data.get('data', {}).get('tasks', [])
match = [t for t in tasks if t.get('name') == '${TASK_NAME}']
if len(match) > 1:
    sys.stderr.write('find_task_id: WARNING %d tasks named ${TASK_NAME} found, using first (id=%s)\n' % (len(match), match[0].get('id')))
if match:
    print(match[0]['id'])
" 2>>"${VAR_DIR}/api.log"
}

build_schedule() {
    local hour="$1"
    if [[ "$API_VER" -eq 4 ]]; then
        printf '{"date_type":0,"hour":0,"minute":0,"repeat_hour":%s,"repeat_min":0,"repeat_date":1001,"week_day":"0,1,2,3,4,5,6","monthly_week":[],"last_work_hour":0,"version":4}' "$hour"
    else
        printf '{"date_type":0,"hour":0,"minute":0,"repeat_hour":%s,"repeat_date":0,"week_day":"0,1,2,3,4,5,6","last_work_hour":0}' "$hour"
    fi
}

ACTION="$1"
shift

case "$ACTION" in
set)
    HOUR="$1"
    if ! [[ "$HOUR" =~ ^([1-9]|1[01])$ ]]; then
        echo '{"success":false,"message":"repeat_hour must be 1-11"}'
        exit 1
    fi

    SCHEDULE=$(build_schedule "$HOUR")
    EXTRA=$(python3 -c "
import json
print(json.dumps({
    'script': '${COMMAND}',
    'notify_enable': False,
    'notify_if_error': False,
    'notify_mail': ''
}))
")

    EXISTING_ID=$(find_task_id)

    if [[ -n "$EXISTING_ID" ]]; then
        # UNVERIFIED: assumes method=set takes the same shape as create + id
        synowebapi -s --exec api=SYNO.Core.TaskScheduler method=set version="$API_VER" \
            id="$EXISTING_ID" name="$TASK_NAME" owner="root" enable=true type="script" \
            schedule="$SCHEDULE" extra="$EXTRA"
    else
        synowebapi -s --exec api=SYNO.Core.TaskScheduler method=create version="$API_VER" \
            name="$TASK_NAME" owner="root" enable=true type="script" \
            schedule="$SCHEDULE" extra="$EXTRA"
    fi
    ;;

disable)
    EXISTING_ID=$(find_task_id)
    if [[ -z "$EXISTING_ID" ]]; then
        echo '{"success":true,"message":"No task to disable"}'
        exit 0
    fi
    synowebapi -s --exec api=SYNO.Core.TaskScheduler method=set_enable version=2 \
        status="[{\"id\":${EXISTING_ID},\"real_owner\":\"root\",\"enable\":false}]"
    ;;

*)
    echo '{"success":false,"message":"Unknown action"}'
    exit 1
    ;;
esac
