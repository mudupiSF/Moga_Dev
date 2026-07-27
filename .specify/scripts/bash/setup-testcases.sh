#!/usr/bin/env bash

set -e

# Parse command line arguments
JSON_MODE=false

for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=true ;;
        --help|-h)
            echo "Usage: $0 [--json]"
            echo "  --json    Output results in JSON format"
            echo "  --help    Show this help message"
            exit 0
            ;;
        *) echo "ERROR: Unknown option '$arg'" >&2; exit 1 ;;
    esac
done

# Source common functions
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Get feature paths
_paths_output=$(get_feature_paths) || { echo "ERROR: Failed to resolve feature paths" >&2; exit 1; }
eval "$_paths_output"
unset _paths_output

# Validate required files
if [[ ! -f "$FEATURE_SPEC" ]]; then
    echo "ERROR: spec.md not found in $FEATURE_DIR" >&2
    echo "Run /speckit-specify first to create the feature structure." >&2
    exit 1
fi

# tasks.md is recommended (gives the tech context for automated test paths) but not required
TASKS_PRESENT=false
[[ -f "$TASKS" ]] && TASKS_PRESENT=true

# Build available docs list (context for richer, more accurate test cases)
docs=()
[[ -f "$IMPL_PLAN" ]] && docs+=("plan.md")
[[ -f "$TASKS" ]] && docs+=("tasks.md")
[[ -f "$DATA_MODEL" ]] && docs+=("data-model.md")
[[ -f "$RESEARCH" ]] && docs+=("research.md")
if [[ -d "$CONTRACTS_DIR" ]] && [[ -n "$(ls -A "$CONTRACTS_DIR" 2>/dev/null)" ]]; then
    docs+=("contracts/")
fi
[[ -f "$QUICKSTART" ]] && docs+=("quickstart.md")

# Output target for the manual/UAT test-case document
TEST_CASES_FILE="$FEATURE_DIR/test-cases.md"

# Resolve the test-cases template through the override stack
TESTCASES_TEMPLATE=$(resolve_template "test-cases-template" "$REPO_ROOT") || true
if [[ -z "$TESTCASES_TEMPLATE" ]] || [[ ! -f "$TESTCASES_TEMPLATE" ]]; then
    echo "ERROR: Could not resolve required test-cases-template from the template override stack for $REPO_ROOT" >&2
    echo "Template 'test-cases-template' was not found. Add an override at .specify/templates/overrides/test-cases-template.md, or reinstall shared infra to restore .specify/templates/test-cases-template.md." >&2
    exit 1
fi

# Output results
if $JSON_MODE; then
    if has_jq; then
        if [[ ${#docs[@]} -eq 0 ]]; then
            json_docs="[]"
        else
            json_docs=$(printf '%s\n' "${docs[@]}" | jq -R . | jq -s .)
        fi
        jq -cn \
            --arg feature_dir "$FEATURE_DIR" \
            --arg spec "$FEATURE_SPEC" \
            --arg tasks "$TASKS" \
            --argjson tasks_present "$TASKS_PRESENT" \
            --arg test_cases_file "$TEST_CASES_FILE" \
            --argjson docs "$json_docs" \
            --arg testcases_template "${TESTCASES_TEMPLATE:-}" \
            '{FEATURE_DIR:$feature_dir,FEATURE_SPEC:$spec,TASKS:$tasks,TASKS_PRESENT:$tasks_present,TEST_CASES_FILE:$test_cases_file,AVAILABLE_DOCS:$docs,TESTCASES_TEMPLATE:$testcases_template}'
    else
        if [[ ${#docs[@]} -eq 0 ]]; then
            json_docs="[]"
        else
            json_docs=$(for d in "${docs[@]}"; do printf '"%s",' "$(json_escape "$d")"; done)
            json_docs="[${json_docs%,}]"
        fi
        printf '{"FEATURE_DIR":"%s","FEATURE_SPEC":"%s","TASKS":"%s","TASKS_PRESENT":%s,"TEST_CASES_FILE":"%s","AVAILABLE_DOCS":%s,"TESTCASES_TEMPLATE":"%s"}\n' \
            "$(json_escape "$FEATURE_DIR")" "$(json_escape "$FEATURE_SPEC")" "$(json_escape "$TASKS")" "$TASKS_PRESENT" "$(json_escape "$TEST_CASES_FILE")" "$json_docs" "$(json_escape "${TESTCASES_TEMPLATE:-}")"
    fi
else
    echo "FEATURE_DIR: $FEATURE_DIR"
    echo "FEATURE_SPEC: $FEATURE_SPEC"
    echo "TEST_CASES_FILE: $TEST_CASES_FILE"
    echo "TESTCASES_TEMPLATE: ${TESTCASES_TEMPLATE:-not found}"
    echo "TASKS_PRESENT: $TASKS_PRESENT"
    echo "AVAILABLE_DOCS:"
    check_file "$IMPL_PLAN" "plan.md"
    check_file "$TASKS" "tasks.md"
    check_file "$DATA_MODEL" "data-model.md"
    check_file "$RESEARCH" "research.md"
    check_dir "$CONTRACTS_DIR" "contracts/"
fi
