#!/usr/bin/env bash
# =============================================================================
# chaos.sh - Chaos Engineering CLI for Voleon DBA Practice Lab
# =============================================================================
# Usage:
#   ./chaos.sh list
#   ./chaos.sh inject  <scenario>   e.g. 01-primary-failover
#   ./chaos.sh validate <scenario>
#   ./chaos.sh status
#   ./chaos.sh results [scenario]
#
# Each scenario lives in chaos/scenarios/<XX-name>/inject.sh + validate.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"
RESULTS_DIR="${SCRIPT_DIR}/results"
LIB_DIR="${SCRIPT_DIR}/lib"

# ---- Colors -----------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---- Bootstrap --------------------------------------------------------------
if [[ ! -f "${LAB_ROOT}/config.sh" ]]; then
    echo -e "${RED}[ERROR]${RESET} config.sh not found at ${LAB_ROOT}/config.sh"
    echo "  Run chaos.sh from within the voleon lab directory."
    exit 1
fi

source "${LAB_ROOT}/config.sh"
source "${LIB_DIR}/common.sh"

mkdir -p "$RESULTS_DIR"

# ---- Helpers ----------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${BOLD}======================================================${RESET}"
    echo -e "${BOLD}  Voleon DBA Lab - Chaos Engineering${RESET}"
    echo -e "${BOLD}======================================================${RESET}"
    echo ""
}

print_usage() {
    echo -e "Usage: ${BOLD}./chaos.sh${RESET} <command> [scenario]"
    echo ""
    echo -e "  ${CYAN}list${RESET}               Show all available scenarios"
    echo -e "  ${CYAN}inject${RESET} <scenario>  Inject chaos into the lab environment"
    echo -e "  ${CYAN}validate${RESET} <scenario> Score your recovery against pass criteria"
    echo -e "  ${CYAN}status${RESET}             Show current lab health (PG, PgBouncer, Docker)"
    echo -e "  ${CYAN}results${RESET} [scenario] Show scores from previous runs"
    echo ""
    echo -e "Examples:"
    echo -e "  ./chaos.sh list"
    echo -e "  ./chaos.sh inject 01-primary-failover"
    echo -e "  ./chaos.sh validate 01-primary-failover"
    echo -e "  ./chaos.sh results"
}

# Resolve a scenario name - accepts full name or just the number prefix.
# Prints the matching scenario directory name, or exits with error.
resolve_scenario() {
    local input="$1"
    local match=""

    for dir in "${SCENARIOS_DIR}"/*/; do
        local name
        name="$(basename "$dir")"
        # Match by full name or by number prefix (e.g. "01" matches "01-primary-failover")
        if [[ "$name" == "$input" || "$name" == ${input}-* ]]; then
            match="$name"
            break
        fi
    done

    if [[ -z "$match" ]]; then
        log_error "Scenario not found: ${input}"
        echo ""
        cmd_list
        exit 1
    fi

    echo "$match"
}

# Return last result status for a scenario: PASS, FAIL, PARTIAL, or "-"
last_result() {
    local scenario="$1"
    local log="${RESULTS_DIR}/${scenario}.log"
    if [[ -f "$log" ]]; then
        tail -1 "$log" | grep -oE 'status=(PASS|FAIL|PARTIAL)' | cut -d= -f2
    else
        echo "-"
    fi
}

status_color() {
    case "$1" in
        PASS)    echo -e "${GREEN}$1${RESET}" ;;
        FAIL)    echo -e "${RED}$1${RESET}" ;;
        PARTIAL) echo -e "${YELLOW}$1${RESET}" ;;
        *)       echo "$1" ;;
    esac
}

# ---- Commands ---------------------------------------------------------------

cmd_list() {
    echo -e "${BOLD}Available Chaos Scenarios${RESET}"
    echo ""
    printf "  %-36s %-10s %s\n" "SCENARIO" "LAST RUN" "STATUS"
    printf "  %-36s %-10s %s\n" "--------" "--------" "------"

    if [[ ! -d "$SCENARIOS_DIR" ]] || [[ -z "$(ls -A "$SCENARIOS_DIR" 2>/dev/null)" ]]; then
        echo "  (no scenarios found in ${SCENARIOS_DIR})"
        return
    fi

    for dir in "${SCENARIOS_DIR}"/*/; do
        local name
        name="$(basename "$dir")"
        local has_inject="no"
        local has_validate="no"
        [[ -f "${dir}/inject.sh" ]]   && has_inject="yes"
        [[ -f "${dir}/validate.sh" ]] && has_validate="yes"

        local last_ts="-"
        local log="${RESULTS_DIR}/${name}.log"
        if [[ -f "$log" ]]; then
            last_ts=$(tail -1 "$log" | cut -d'|' -f1 | tr -d ' ' | cut -dT -f1 2>/dev/null || echo "-")
            last_ts=$(tail -1 "$log" | awk -F'|' '{print $1}' | xargs | cut -c1-10)
        fi

        local status
        status=$(last_result "$name")
        local ready=""
        [[ "$has_inject" == "yes" && "$has_validate" == "yes" ]] && ready="" || ready=" ${YELLOW}[incomplete]${RESET}"

        printf "  %-36s %-10s " "$name" "$last_ts"
        echo -e "$(status_color "$status")${ready}"
    done
    echo ""
}

cmd_inject() {
    local input="${1:-}"
    if [[ -z "$input" ]]; then
        log_error "inject requires a scenario name. Run './chaos.sh list' to see options."
        exit 1
    fi

    local scenario
    scenario=$(resolve_scenario "$input")
    local inject_script="${SCENARIOS_DIR}/${scenario}/inject.sh"

    if [[ ! -f "$inject_script" ]]; then
        log_error "inject.sh not found for scenario: ${scenario}"
        exit 1
    fi

    echo ""
    echo -e "${BOLD}Scenario:${RESET} ${scenario}"
    echo -e "${RED}${BOLD}Injecting chaos...${RESET}"
    echo ""

    timer_start
    bash "$inject_script"
    local exit_code=$?
    local elapsed
    elapsed=$(timer_stop)

    echo ""
    if (( exit_code == 0 )); then
        log_success "Injection complete in ${elapsed}s. Start your recovery now."
        echo ""
        echo -e "  When resolved, run: ${BOLD}./chaos.sh validate ${scenario}${RESET}"
    else
        log_error "inject.sh exited with code ${exit_code} after ${elapsed}s."
    fi
    echo ""
}

cmd_validate() {
    local input="${1:-}"
    if [[ -z "$input" ]]; then
        log_error "validate requires a scenario name. Run './chaos.sh list' to see options."
        exit 1
    fi

    local scenario
    scenario=$(resolve_scenario "$input")
    local validate_script="${SCENARIOS_DIR}/${scenario}/validate.sh"

    if [[ ! -f "$validate_script" ]]; then
        log_error "validate.sh not found for scenario: ${scenario}"
        exit 1
    fi

    echo ""
    echo -e "${BOLD}Scenario:${RESET} ${scenario}"
    echo -e "${CYAN}${BOLD}Validating your recovery...${RESET}"
    echo ""

    timer_start
    bash "$validate_script"
    local exit_code=$?
    local elapsed
    elapsed=$(timer_stop)

    echo ""
    if (( exit_code == 0 )); then
        log_success "Validation PASSED in ${elapsed}s."
        record_result "$scenario" "PASS" "$elapsed"
    else
        log_error "Validation FAILED after ${elapsed}s. Review the output above."
        record_result "$scenario" "FAIL" "$elapsed"
    fi
    echo ""
}

cmd_status() {
    echo -e "${BOLD}Current Lab Health${RESET}"
    echo ""

    local nodes=(
        "primary:${PRIMARY_HOST}"
        "replica:${REPLICA_HOST}"
        "container:${CONTAINER_HOST}"
        "ops:${OPS_HOST}"
    )

    printf "  %-14s %-18s %-8s %-12s\n" "NODE" "HOST" "SSH" "POSTGRES"
    printf "  %-14s %-18s %-8s %-12s\n" "----" "----" "---" "--------"

    for entry in "${nodes[@]}"; do
        local label="${entry%%:*}"
        local host="${entry##*:}"

        local ssh_ok pg_ok
        check_ssh "$host" && ssh_ok="${GREEN}UP${RESET}" || ssh_ok="${RED}DOWN${RESET}"
        check_pg  "$host" && pg_ok="${GREEN}UP${RESET}"  || pg_ok="${RED}DOWN${RESET}"

        printf "  %-14s %-18s " "$label" "$host"
        echo -e "${ssh_ok}       ${pg_ok}"
    done

    echo ""
    echo -e "  ${BOLD}PgBouncer${RESET} (${PRIMARY_HOST}:${PGBOUNCER_PORT})"
    check_port "$PRIMARY_HOST" "$PGBOUNCER_PORT" \
        && echo -e "    ${GREEN}UP${RESET} - port ${PGBOUNCER_PORT} is open" \
        || echo -e "    ${RED}DOWN${RESET} - port ${PGBOUNCER_PORT} not reachable"

    echo ""
    echo -e "  ${BOLD}Docker PG${RESET} (${CONTAINER_HOST}:${DOCKER_PG_PORT})"
    check_pg "$CONTAINER_HOST" "$DOCKER_PG_PORT" \
        && echo -e "    ${GREEN}UP${RESET} - accepting connections on port ${DOCKER_PG_PORT}" \
        || echo -e "    ${RED}DOWN${RESET} - not responding on port ${DOCKER_PG_PORT}"

    echo ""
    echo -e "  ${BOLD}Prometheus${RESET} (${OPS_HOST}:${PROMETHEUS_PORT})"
    check_port "$OPS_HOST" "$PROMETHEUS_PORT" \
        && echo -e "    ${GREEN}UP${RESET} - port ${PROMETHEUS_PORT} is open" \
        || echo -e "    ${RED}DOWN${RESET} - port ${PROMETHEUS_PORT} not reachable"
    echo ""
}

cmd_results() {
    local filter="${1:-}"

    echo -e "${BOLD}Chaos Engineering Results${RESET}"
    echo ""

    if [[ -n "$filter" ]]; then
        local scenario
        scenario=$(resolve_scenario "$filter")
        local log="${RESULTS_DIR}/${scenario}.log"
        if [[ ! -f "$log" ]]; then
            echo "  No results yet for: ${scenario}"
            return
        fi
        echo -e "  ${BOLD}${scenario}${RESET}"
        while IFS= read -r line; do
            local status
            status=$(echo "$line" | grep -oE 'status=(PASS|FAIL|PARTIAL)' | cut -d= -f2)
            echo -e "    $(status_color "$status")  ${line}"
        done < "$log"
    else
        local summary="${RESULTS_DIR}/summary.log"
        if [[ ! -f "$summary" ]] || [[ ! -s "$summary" ]]; then
            echo "  No results yet. Run './chaos.sh inject <scenario>' to start."
            return
        fi
        while IFS= read -r line; do
            local status
            status=$(echo "$line" | grep -oE 'status=(PASS|FAIL|PARTIAL)' | cut -d= -f2)
            echo -e "  $(status_color "$status")  ${line}"
        done < "$summary"
    fi
    echo ""

    # Summary counts
    if [[ -f "${RESULTS_DIR}/summary.log" ]]; then
        local pass fail partial
        pass=$(grep -c 'status=PASS'    "${RESULTS_DIR}/summary.log" 2>/dev/null || echo 0)
        fail=$(grep -c 'status=FAIL'    "${RESULTS_DIR}/summary.log" 2>/dev/null || echo 0)
        partial=$(grep -c 'status=PARTIAL' "${RESULTS_DIR}/summary.log" 2>/dev/null || echo 0)
        echo -e "  Totals - ${GREEN}PASS: ${pass}${RESET}  ${RED}FAIL: ${fail}${RESET}  ${YELLOW}PARTIAL: ${partial}${RESET}"
        echo ""
    fi
}

# ---- Entry Point ------------------------------------------------------------

print_header

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
    list)                    cmd_list ;;
    inject)                  cmd_inject "${1:-}" ;;
    validate)                cmd_validate "${1:-}" ;;
    status)                  cmd_status ;;
    results)                 cmd_results "${1:-}" ;;
    help|--help|-h)          print_usage ;;
    *)
        log_error "Unknown command: ${COMMAND}"
        echo ""
        print_usage
        exit 1
        ;;
esac
