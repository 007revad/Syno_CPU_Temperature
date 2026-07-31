#!/bin/bash
#----------------------------------------------------------
# CPU Temperature package - API CGI
#----------------------------------------------------------

# --------- 1. Common variables and path calculations -------------

PKG_NAME="CPUTemp"
PKG_ROOT="/var/packages/${PKG_NAME}"
TARGET_DIR="${PKG_ROOT}/target"
BIN_DIR="${TARGET_DIR}/bin"

# Get DSM major version
dsm=$(/usr/syno/bin/synogetkeyvalue /etc.defaults/VERSION majorversion)
if [[ $dsm -ge 7 ]]; then
    VAR_DIR="${PKG_ROOT}/var"
else
    VAR_DIR="${PKG_ROOT}/etc"
fi

LOG_FILE="${VAR_DIR}/api.log"

API_SCRIPT="${BIN_DIR}/cpu_temp_api.sh"

touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

# --------- 2. HTTP header output --------------------------------

echo "Content-Type: application/json; charset=utf-8"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST"
echo "Access-Control-Allow-Headers: Content-Type"
echo "" # Header/body separator blank line

# --------- 3. Parsing URL-encoded parameters --------------------

urldecode() { : "${*//+/ }"; echo -e "${_//%/\\x}"; }
declare -A PARAM
parse_kv() {
    local kv_pair key val
    IFS='&' read -ra kv_pair <<< "$1"
    for pair in "${kv_pair[@]}"; do
        IFS='=' read -r key val <<< "${pair}"
        key="$(urldecode "${key}")"
        val="$(urldecode "${val}")"
        PARAM["${key}"]="${val}"
    done
}

case "$REQUEST_METHOD" in
POST)
    CONTENT_LENGTH=${CONTENT_LENGTH:-0}
    if [ "$CONTENT_LENGTH" -gt 0 ]; then
        read -r -n "$CONTENT_LENGTH" POST_DATA
    else
        POST_DATA=""
    fi
    parse_kv "${POST_DATA}"
    ;;
GET)
    parse_kv "${QUERY_STRING}"
    ;;
*)
    log "Unsupported METHOD: ${REQUEST_METHOD}"
    echo '{"success":false,"message":"Unsupported METHOD","result":null}'
    exit 0
    ;;
esac

ACTION="${PARAM[action]}"
log "Request: ACTION=${ACTION}"

# --------- 4. JSON utility functions -----------------------------

json_response() {
    local ok="$1" msg="$2" data="$3"
    local msg_json
    msg_json=$(echo "$msg" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')
    if [ -z "$data" ]; then
        echo "{\"success\":$ok, \"message\":$msg_json, \"result\":null}"
    else
        echo "{\"success\":$ok, \"message\":$msg_json, \"result\":$data}"
    fi
}

# Runs the privileged wrapper via sudo -n and captures stdout/rc.
# Sets RUN_RC and RUN_OUT.
run_privileged() {
    RUN_OUT=$(sudo -n "$API_SCRIPT" "$@" 2>>"${LOG_FILE}")
    RUN_RC=$?
}

# --------- 5. Action processing ---------------------------------

case "${ACTION}" in
init)
    log "----------------------------------------"
    log "Web UI opened/refreshed"
    echo '{"success":true,"message":"init"}'
    ;;

run)
    run_privileged run
    if [ "$RUN_RC" -ne 0 ] || [ -z "$RUN_OUT" ]; then
        log "[ERROR] run failed (rc=${RUN_RC}): ${RUN_OUT}"
        json_response false "Failed to run syno_cpu_temp.sh. Check sudoers grant." ""
    else
        echo "$RUN_OUT"
    fi
    ;;

getlog)
    run_privileged getlog
    if [ "$RUN_RC" -ne 0 ]; then
        log "[ERROR] getlog failed (rc=${RUN_RC}): ${RUN_OUT}"
        json_response false "Could not read log" ""
    else
        # RUN_OUT is a JSON-encoded string (the log contents)
        json_response true "" "${RUN_OUT}"
    fi
    ;;

getsettings)
    run_privileged getsettings
    if [ "$RUN_RC" -ne 0 ] || [ -z "$RUN_OUT" ]; then
        log "[ERROR] getsettings failed (rc=${RUN_RC}): ${RUN_OUT}"
        json_response false "Could not read settings" ""
    else
        echo "$RUN_OUT"
    fi
    ;;

setsettings)
    LOG_ENABLED="${PARAM[log_enabled]}"
    LOG_DAYS="${PARAM[log_days]}"
    FREQUENCY="${PARAM[frequency]}"
    run_privileged setsettings "$LOG_ENABLED" "$LOG_DAYS" "$FREQUENCY"
    if [ "$RUN_RC" -ne 0 ]; then
        log "[ERROR] setsettings failed (rc=${RUN_RC}): ${RUN_OUT}"
        json_response false "${RUN_OUT:-Failed to save settings}" ""
    else
        echo "$RUN_OUT"
    fi
    ;;

*)
    log "[ERROR] Invalid action: ${ACTION}"
    json_response false "Invalid action: ${ACTION}" ""
    ;;
esac

exit 0
