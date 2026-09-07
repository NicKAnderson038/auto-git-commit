#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Load Environment Variables ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
    echo "Loading configuration from $SCRIPT_DIR/.env"
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
else
    echo "Error: .env file not found at $SCRIPT_DIR/.env"
    exit 1
fi

if [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: GEMINI_API_KEY is empty or not set in your .env file."
    exit 1
fi

# --- Configuration ---
MAIN_BRANCH="main"
FEATURE_BRANCH="origin/feature-branch" # Replace with your actual upstream branch
PRE_COMMIT_CMD="npm run lint && npm run format" # Replace with your actual lint/format commands
MODEL="gemini-1.5-flash"

# Helper function to send prompts to the Gemini API
ask_gemini() {
    local prompt="$1"
    local escaped_prompt=$(echo "$prompt" | jq -Rsa .)

    local response=$(curl -s -X POST "https://googleapis.com{MODEL}:generateContent?key=${GEMINI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"contents\": [{\"parts\": [{\"text\": ${escaped_prompt}}]}]}")

    echo "$response" | jq -r '.candidates.content.parts.text // empty'
}

echo "========== 0. Staging all local working changes =========="
git add .

echo "========== 1. Fetching latest code =========="
git checkout "$MAIN_BRANCH"
git pull origin "$MAIN_BRANCH"
git fetch --all

echo "========== 2. Attempting merge =========="
echo "Attempting to merge $FEATURE_BRANCH into $MAIN_BRANCH..."
set +e
git merge "$FEATURE_BRANCH" --no-commit --no-ff
MERGE_STATUS=$?
set -e

if [ $MERGE_STATUS -ne 0 ]; then
    echo "Merge conflicts detected! Invoking Gemini to resolve..."
    
    CONFLICTED_FILES=$(git diff --name-only --diff-filter=U)
    
    for file in $CONFLICTED_FILES; do
        echo "Gemini processing conflict in: $file"
        FILE_CONTENT=$(cat "$file")
        
        PROMPT="You are an expert software engineer. Below is a code file that contains Git merge conflict markers (<<<<<<<, =======, >>>>>>>). Resolve the conflicts intelligently, choosing the best version of the code. Remove all git conflict markers. Return ONLY the raw, completed code file text. Absolutely do not include markdown code block wrappers (like \`\`\`), do not include explanations, and do not add conversational text. Just output the clean file text:\n\n$FILE_CONTENT"
        
        RESOLVED_CONTENT=$(ask_gemini "$PROMPT")
        
        if echo "$RESOLVED_CONTENT" | grep -q "^\`\`\`"; then
            RESOLVED_CONTENT=$(echo "$RESOLVED_CONTENT" | sed '1d;$d')
        fi
        
        echo "$RESOLVED_CONTENT" > "$file"
        git add "$file"
    done
    echo "Gemini conflict resolution complete."
else
    echo "No merge conflicts detected. Proceeding normally."
fi

echo "========== 3. Creating a new branch based on changes =========="
STAGED_DIFF=$(git diff --cached --stat)

if [ -z "$STAGED_DIFF" ]; then
    echo "Error: No staged changes found to commit. Make sure you edited your files."
    exit 1
fi

BRANCH_PROMPT="Analyze the following git diff summary of the code changes being committed. Based strictly on the context of what these changes do, suggest a single, short, lowercase, hyphenated branch name (e.g., feature-auth-fix or bugfix-login-error). Return ONLY the branch name string. No punctuation, no quotes, no explanation, no markdown. Changes:\n$STAGED_DIFF"

RAW_BRANCH_NAME=$(ask_gemini "$BRANCH_PROMPT")

AI_BRANCH_NAME=$(echo "$RAW_BRANCH_NAME" | tr -d '"'\''`' | tr ' ' '-' | tr -d '\r\n' | sed 's/[^a-zA-Z0-9-]*//g' | tr '[:upper:]' '[:lower:]')

if [ -z "$AI_BRANCH_NAME" ] || [ "$AI_BRANCH_NAME" = "null" ]; then
    AI_BRANCH_NAME="deploy-gemini-ai-$(date +%Y%m%d%H%M%S)"
fi

echo "Creating and switching to branch: $AI_BRANCH_NAME"
git checkout -b "$AI_BRANCH_NAME"

# echo "========== 4. Running pre-commit formatting and linting =========="
# echo "Running: $PRE_COMMIT_CMD"
# eval "$PRE_COMMIT_CMD"
git add -A

echo "========== 5. Generating Gemini Commit Message & Committing =========="
FINAL_DIFF=$(git diff --cached --stat)

COMMIT_PROMPT="Analyze the following git diff summary of the changes being committed. Write a short, professional, one-line git commit message describing exactly what these changes accomplish. Return ONLY the string. Do not use quotes, do not give an explanation, do not include prefixes like 'Commit message:' or markdown code blocks. Changes:\n$FINAL_DIFF"

RAW_COMMIT_MSG=$(ask_gemini "$COMMIT_PROMPT")

AI_COMMIT_MSG=$(echo "$RAW_COMMIT_MSG" | tr -d '"'\''`' | tr -d '\r\n' | sed 's/^Commit message: //I')

if [ -z "$AI_COMMIT_MSG" ] || [ "$AI_COMMIT_MSG" = "null" ]; then
    AI_COMMIT_MSG="Automated Gemini deployment on $(date)"
fi

echo "Committing with message: $AI_COMMIT_MSG"
git commit -m "$AI_COMMIT_MSG"

echo "========== 6. Pushing new branch to remote repository =========="
git push origin "$AI_BRANCH_NAME"

# echo "========== 7. Post-push cleanup & sync =========="
# # Get the exact unique commit hash we just pushed
# LOCAL_COMMIT_HASH=$(git rev-parse HEAD)

# echo "Switching back to local $MAIN_BRANCH branch..."
# git checkout "$MAIN_BRANCH"

# echo "Waiting for remote main branch to include our new commit..."
# MAX_ATTEMPTS=30
# ATTEMPT=1
# MERGED=false

# while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
#     # Fetch remote main status silently
#     git fetch origin "$MAIN_BRANCH" > /dev/null 2>&1
    
#     # Check if our commit hash exists inside the history of origin/main
#     if git merge-base --is-ancestor "$LOCAL_COMMIT_HASH" "origin/$MAIN_BRANCH" 2>/dev/null; then
#         echo "Success! Detected our commit inside the remote main branch history."
#         MERGED=true
#         break
#     fi

#     echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Commit not merged yet. Retrying in 10 seconds..."
#     sleep 10
#     ATTEMPT=$((ATTEMPT + 1))
# done

# if [ "$MERGED" = "false" ]; then
#     echo "Warning: Auto-merge timed out on the remote repository."
# else
#     echo "Pulling down the newly auto-merged changes..."
#     git pull origin "$MAIN_BRANCH"
# fi

# echo "Deleting the temporary feature branch locally ($AI_BRANCH_NAME)..."
# git branch -D "$AI_BRANCH_NAME"
