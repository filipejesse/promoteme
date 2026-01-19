#!/bin/bash

# promoteme.sh
# CLI to generate brag documents based on GitHub contributions.

set -e

# Default configuration
PER_PAGE=30
DATE_FILTER=""
LANGUAGE=""
AI_MODEL="gemini"
ORG_FILTER=""
REPO_FILTER=""
NOTES_DIR=""

# check dependencies
if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI ('gh') is not installed."
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq is not installed. Please install it to use this script."
    exit 1
fi

# check auth
if ! gh auth status &>/dev/null; then
    echo "Error: You are not logged into GitHub CLI. Run 'gh auth login' first."
    exit 1
fi

# Get current user
CURRENT_USER=$(gh api user --jq .login)
if [[ -z "$CURRENT_USER" ]]; then
    echo "Error: Could not retrieve current GitHub user."
    exit 1
fi

function print_usage() {
    echo "Usage: $0 <command> [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  generate             Generate brag document from GitHub contributions"
    echo ""
    echo "Options:"
    echo "  --start-date DATE    Start date (YYYY-MM-DD). Default: 6 months ago"
    echo "  --end-date DATE      End date (YYYY-MM-DD). Default: today"
    echo "  --org=ORG1,ORG2      Filter by organization(s), comma-separated."
    echo "  --repo=REPO1,REPO2   Filter by repository(s), comma-separated (format: owner/repo)."
    echo "  -l, --language LANG  Output language for the Brag Document (e.g., 'English', 'Portuguese')."
    echo "  -m, --model MODEL    Specify the AI model to use (default: 'gemini')."
    echo "  --notes=PATH         Directory with personal notes (.md/.txt) about non-code contributions."
    echo "  --help               Show this help message."
}

# Check for subcommand
COMMAND="${1:-}"

# No arguments = show help
if [[ -z "$COMMAND" ]]; then
    print_usage
    exit 0
fi

# If --help at command position, show help
if [[ "$COMMAND" == "--help" ]]; then
    print_usage
    exit 0
fi

# Validate command
if [[ "$COMMAND" != "generate" ]]; then
    echo "Unknown command: $COMMAND"
    print_usage
    exit 1
fi

# Shift past the command for option parsing
shift

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
    --start-date)
        START_DATE="$2"
        shift
        ;;
    --end-date)
        END_DATE="$2"
        shift
        ;;
    -l | --language)
        LANGUAGE="$2"
        shift
        ;; # New: Language parameter
    -m | --model)
        AI_MODEL="$2"
        shift
        ;;
    --org=*)
        ORG_FILTER="${1#*=}"
        ;;
    --repo=*)
        REPO_FILTER="${1#*=}"
        ;;
    --notes=*)
        NOTES_DIR="${1#*=}"
        ;;
    --help)
        print_usage
        exit 0
        ;;
    *)
        echo "Unknown parameter passed: $1"
        print_usage
        exit 1
        ;;
    esac
    shift
done

# Default: last 6 months if no dates provided
if [[ -z "$START_DATE" && -z "$END_DATE" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
        START_DATE=$(date -v-6m +%Y-%m-%d)
    else
        START_DATE=$(date -d '6 months ago' +%Y-%m-%d)
    fi
    END_DATE=$(date +%Y-%m-%d)
fi

# Construct date filter
if [[ -n "$START_DATE" && -n "$END_DATE" ]]; then
    DATE_FILTER="created:${START_DATE}..${END_DATE}"
elif [[ -n "$START_DATE" ]]; then
    DATE_FILTER="created:>=${START_DATE}"
elif [[ -n "$END_DATE" ]]; then
    DATE_FILTER="created:<=${END_DATE}"
fi

# Function to fetch PRs
function fetch_prs() {
    echo "Fetching PRs for user: $CURRENT_USER..." >&2

    QUERY="author:$CURRENT_USER type:pr"
    if [[ -n "$DATE_FILTER" ]]; then
        QUERY="$QUERY $DATE_FILTER"
    fi

    # Add org filter
    if [[ -n "$ORG_FILTER" ]]; then
        IFS=',' read -ra ORGS <<< "$ORG_FILTER"
        for org in "${ORGS[@]}"; do
            QUERY="$QUERY org:$org"
        done
    fi

    # Add repo filter
    if [[ -n "$REPO_FILTER" ]]; then
        IFS=',' read -ra REPOS <<< "$REPO_FILTER"
        for repo in "${REPOS[@]}"; do
            QUERY="$QUERY repo:$repo"
        done
    fi

    # Using gh api with pagination
    # We utilize --paginate to automatically traverse all pages
    # We set per_page to 30 as requested
    # Explicitly force GET method
    gh api -X GET search/issues \
        -f q="$QUERY" \
        --paginate \
        -f per_page=$PER_PAGE \
        --jq '.items[] | {title: .title, url: .html_url, repo: .repository_url, created_at: .created_at, state: .state}'
}

# Function to process a single PR
process_pr() {
    local url="$1"
    local title="$2"
    local state="$3"
    local created_at="$4"

    # Fetch details including files to check for tests
    PR_JSON=$(gh pr view "$url" --json body,files,additions,deletions 2>/dev/null || echo "")

    if [[ -n "$PR_JSON" ]]; then
        # 1. Scope (Title)
        echo "- **Scope:** $title"

        # 2. Impact (Diff Stats)
        ADDITIONS=$(echo "$PR_JSON" | jq '.additions')
        DELETIONS=$(echo "$PR_JSON" | jq '.deletions')
        TOTAL_CHANGES=$((ADDITIONS + DELETIONS))

        echo "- **Impact:** $TOTAL_CHANGES lines changed (+$ADDITIONS / -$DELETIONS)."

        # 3. Risk (Heuristic based on size)
        if [[ "$TOTAL_CHANGES" -gt 500 ]]; then
            RISK="High (Large changeset)"
        elif [[ "$TOTAL_CHANGES" -gt 200 ]]; then
            RISK="Medium (Moderate changeset)"
        else
            RISK="Low (Small changeset)"
        fi
        echo "- **Risk:** $RISK"

        # 4. Action
        if [[ "$state" == "OPEN" ]]; then
            ACTION="Needs Review"
        elif [[ "$state" == "MERGED" ]]; then
            ACTION="No action (Merged)"
        else
            ACTION="No action (Closed)"
        fi
        echo "- **Action:** $ACTION"

        # 5. Tests (Check for test files)
        TEST_FILES=$(echo "$PR_JSON" | jq -r '.files[].path' | grep -E 'test|spec' | head -n 3)
        if [[ -n "$TEST_FILES" ]]; then
            echo "- **Tests:** Verified. (Found: $(echo "$TEST_FILES" | tr '\n' ' ' | sed 's/ $//')...)"
        else
            echo "- **Tests:** No explicit test files detected."
        fi

        # Link for reference
        echo "  ([View PR]($url))"
        echo ""
    else
        echo "⚠️ Could not fetch details for $title"
    fi
}

# Function to collect notes from a directory
function collect_notes() {
    local dir="$1"
    local content=""

    if [[ -d "$dir" ]]; then
        for f in "$dir"/*.md "$dir"/*.txt; do
            [[ -f "$f" ]] || continue
            content+=$'\n\n---\n'
            content+="Notes from $(basename "$f"):\n"
            content+=$(cat "$f")
        done
    fi
    echo "$content"
}

# Main execution
# Determine output directory name
# If dates are missing, use "ALL_TIME" or "SINCE_START" etc.
if [[ -n "$START_DATE" && -n "$END_DATE" ]]; then
    DIR_SUFFIX="${START_DATE}_${END_DATE}"
elif [[ -n "$START_DATE" ]]; then
    DIR_SUFFIX="${START_DATE}_ONWARDS"
elif [[ -n "$END_DATE" ]]; then
    DIR_SUFFIX="UNTIL_${END_DATE}"
else
    DIR_SUFFIX="ALL_TIME"
fi

OUTPUT_DIR="${CURRENT_USER}"
mkdir -p "$OUTPUT_DIR"
echo "📂 Output directory created: $OUTPUT_DIR"

echo "# Brag Document"
if [[ -n "$DATE_FILTER" ]]; then
    echo "## Period: $DATE_FILTER"
fi
echo ""

# We capture the output of fetch_prs into a temporary file or variable to process it.
# Since we need to group by repo, saving to a temp file is safer for large datasets.
TMP_FILE=$(mktemp)
fetch_prs >"$TMP_FILE"

# Check if we found anything
if [[ ! -s "$TMP_FILE" ]]; then
    echo "No contributions found for the specified criteria."
    rm "$TMP_FILE"
    exit 0
fi

# Iterate over all PRs found, grouped by repo
cat "$TMP_FILE" | jq -s -c 'map(.repo |= sub("https://api.github.com/repos/"; "")) | group_by(.repo)[]' | while read -r group; do
    # Extract repo name from the first element of the group
    REPO_NAME=$(echo "$group" | jq -r '.[0].repo' | tr '/' '_') # replace / with _ for filename
    REPO_DISPLAY_NAME=$(echo "$group" | jq -r '.[0].repo')

    echo "Processing repository: $REPO_DISPLAY_NAME..."

    # Generate the Raw Report for this repository
    REPO_RAW_REPORT="# Report for $REPO_DISPLAY_NAME\n\n"
    while read -r pr; do
        _URL=$(echo "$pr" | jq -r '.url')
        _TITLE=$(echo "$pr" | jq -r '.title')
        _STATE=$(echo "$pr" | jq -r '.state')
        _CREATED=$(echo "$pr" | jq -r '.created_at')

        # Capture the output of process_pr
        PR_OUTPUT=$(process_pr "$_URL" "$_TITLE" "$_STATE" "$_CREATED")
        REPO_RAW_REPORT="${REPO_RAW_REPORT}\n${PR_OUTPUT}"
    done < <(echo "$group" | jq -c '.[]')

    # Save Raw Report directly to the output file
    SUMMARY_FILE="$OUTPUT_DIR/${REPO_NAME}.md"
    echo -e "$REPO_RAW_REPORT" >"$SUMMARY_FILE"

    echo "✅ Saved raw report: $SUMMARY_FILE"
done

# Generate notes summary if notes directory provided
if [[ -n "$NOTES_DIR" && -d "$NOTES_DIR" ]]; then
    NOTES_CONTENT=$(collect_notes "$NOTES_DIR")
    if [[ -n "$NOTES_CONTENT" ]]; then
        NOTES_SUMMARY_FILE="$OUTPUT_DIR/NOTES_SUMMARY.md"
        echo "🤖 Generating notes summary..."

        NOTES_PROMPT="Summarize these personal notes about team contributions, leadership, and non-code impact. Focus on: collaboration, mentorship, process improvements, cross-team work. Output in markdown."
        if [[ -n "$LANGUAGE" ]]; then
            NOTES_PROMPT+=" Output in $LANGUAGE."
        fi
        NOTES_PROMPT+="$NOTES_CONTENT"

        if command -v "$AI_MODEL" &>/dev/null; then
            "$AI_MODEL" -p "$NOTES_PROMPT" > "$NOTES_SUMMARY_FILE"
            echo "✅ Notes summary: $NOTES_SUMMARY_FILE"
        fi
    fi
fi

# Final Consolidation: Generate README.md
FINAL_DOC="$OUTPUT_DIR/README.md"
echo "🤖 Generating final consolidated brag document..."

AI_CLI="$AI_MODEL"

if command -v "$AI_CLI" &>/dev/null; then
    # Construct the prompt for the final summary
    FINAL_PROMPT=$(cat PROMPT.txt)
    FINAL_PROMPT+=$'\n\nTask: Synthesize the following repository summaries into a single, cohesive Brag Document for the entire period. Highlight the overall impact across all projects.'
    FINAL_PROMPT+=$'\n\nAdditionally, after the main executive summary and highlights, please provide a dedicated section titled "Repository Breakdown". For EACH repository found in the input, provide a summary using this format:\n'
    FINAL_PROMPT+=$'### [Project Name]\n'
    FINAL_PROMPT+=$'- **Key Features:** List 2-3 main features or changes delivered.\n'
    FINAL_PROMPT+=$'- **Business Value:** Explain the tangible benefit (e.g., "Improved user experience," "Reduced build time").\n'
    FINAL_PROMPT+=$'- **Technical Stack:** inferred from the context (e.g., React, Next.js, Go).\n'

    # Append language instruction if specified
    if [[ -n "$LANGUAGE" ]]; then
        FINAL_PROMPT=$(printf "%s\n\nPlease provide the output in %s." "$FINAL_PROMPT" "$LANGUAGE")
    fi

    REPO_CONTENT=""
    for f in "$OUTPUT_DIR"/*.md; do
        if [[ "$f" != "$FINAL_DOC" && "$f" != "$OUTPUT_DIR/NOTES_SUMMARY.md" ]]; then
            REPO_CONTENT+=$'\n\n---\n'
            REPO_CONTENT+="Content from $(basename "$f"):\n"
            REPO_CONTENT+=$(cat "$f")
        fi
    done
    FINAL_PROMPT+="$REPO_CONTENT"

    # Append personal notes if provided
    if [[ -n "$NOTES_DIR" && -d "$NOTES_DIR" ]]; then
        NOTES_CONTENT=$(collect_notes "$NOTES_DIR")
        if [[ -n "$NOTES_CONTENT" ]]; then
            FINAL_PROMPT+=$'\n\n---\n'
            FINAL_PROMPT+="PERSONAL NOTES (non-code contributions, team impact, leadership):\n"
            FINAL_PROMPT+="$NOTES_CONTENT"
        fi
    fi
    "$AI_CLI" -p "$FINAL_PROMPT" >"$FINAL_DOC"
    echo "✅ Final document generated using $AI_CLI: $FINAL_DOC"
else
    echo "⚠️ '$AI_CLI' CLI not found. Concatenating files instead."
    echo "# Brag documents - $DIR_SUFFIX" >"$FINAL_DOC"
    for f in "$OUTPUT_DIR"/*.md; do
        if [[ "$f" != "$FINAL_DOC" ]]; then
            echo "" >>"$FINAL_DOC"
            cat "$f" >>"$FINAL_DOC"
        fi
    done
    echo "✅ Final Brag Document concatenated: $FINAL_DOC"
fi

# Cleanup
rm "$TMP_FILE"
