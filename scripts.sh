#!/bin/bash

LOGIN_URL="https://archlinux.org/admin/login/"
COOKIE_FILE="cookies.txt"

JSON_FILE="json_response.json"

get_problem_urls() {
    t=$(shuf -i 0-9 -n1)
    sleep 0."$t"
    # jq '.urls[]
    #     | select( .score > 100  or .score == null or .delay > 259200)
    #     | if type == "object" then del(.logs) else . end
    #     | {url,Delay, last_sync, score}' all_mirrors.json

    curl https://archlinux.org/mirrors/"$1"/json/ |
        jq '.urls[]
        | select( .score > 100  or .score == null or .delay > 259200)
        | if type == "object" then del(.logs) else . end
        | {url,Delay, last_sync, score}' | tr -d '\{\}'
}

compose_email() {
    #1 mirror name
    #2 mirror email
    #3 mirror stats
    # echo "Composing email to: $mirror, checking if composed: $mirror.composed "
    # if [ ! -e "$mirror.composed" ]; then
    #     touch "$mirror".composed
    #     echo "$2" >>"$mirror".composed
    #     echo "$3" >>"$mirror".composed
    # else
    #     echo "Mirror $mirror already messaged"
    #     return
    # fi

    thunderbird -compose "from='pitastrudl@archlinux.org',subject='Problem with $1 Arch Linux mirror',to='$2',body='Hi,

    We have noticed that your Arch Linux mirror / URL $1 is currently not functional. Please investigate the issue at your earliest convenience and let us know once it has been resolved. If the issue persists for too long, the mirror or URLs may eventually be disabled. Thank you very much.

    Below are some values of the problematic URLs from the Arch Linux website https://archlinux.org/mirrors/$1 where you will find some more information about the values as well.

    $3

    Best regards,
    Arun
    Arch Linux mirror team
                '" &

}

check_if_sent() {
    # $1 = recipient email to check
    RECIPIENT="$1"

    # Define the SQLite database path
    DB_PATH="/home/arun/.thunderbird/zwzshc74.default-release/global-messages-db.sqlite"

    # Check if the database exists
    if [[ ! -f "$DB_PATH" ]]; then
        echo "❌ ERROR: Thunderbird database not found at $DB_PATH"
        return 2 # Exit code 2 for missing database
    fi

    # Ensure the copy is in DELETE mode to prevent WAL file issues
    sqlite3 global-messages-db.copy.sqlite "PRAGMA journal_mode = DELETE" >/dev/null 2>&1

    # Check if email exists in skip list
    SKIP_FILE="skip_emails.txt"
    CLEAN_RECIPIENT=$(echo "$RECIPIENT" | xargs) # Trim recipient whitespace
    if [[ -f "$SKIP_FILE" ]]; then
        while IFS= read -r line; do
            SKIP_EMAIL=$(echo "$line" | xargs) # Trim whitespace

            cmp -s <(echo -n "$CLEAN_RECIPIENT") <(echo -n "$SKIP_EMAIL")
            echo "cmp exit code: $?"
            echo "clean recepient is1: $CLEAN_RECIPIENT and skip email is $SKIP_EMAIL"

            if [[ "$CLEAN_RECIPIENT" == "$SKIP_EMAIL" ]]; then
                return 0 # Exit with code 3 (email skipped)
            fi
        done <"$SKIP_FILE"
    fi
    echo "clean recepient is2: $CLEAN_RECIPIENT"
    # Define SQL Query
    SQL_QUERY="
    SELECT count(*) FROM messages m
    JOIN messagesText_content mtc ON m.id = mtc.docid
    WHERE m.folderID IN (
        SELECT id FROM folderLocations
        WHERE name LIKE '%Sent%'
        OR name LIKE '%mirror_cleanup%'  -- Check additional folder
    )
    AND mtc.c3author LIKE '%pitastrudl@archlinux.org%'  -- Match sender email
    AND m.date >= (strftime('%s', 'now', '-58 days') * 1000000)  -- Only last 40 days
    AND mtc.c1subject LIKE '%Problem with%'
    AND mtc.c4recipients LIKE '%$CLEAN_RECIPIENT%'
    ORDER BY m.date DESC
    LIMIT 50;
    "

    # Run the query and store the result
    RESULT=$(sqlite3 global-messages-db.copy.sqlite "$SQL_QUERY")
    echo "$RESULT" >>result.log

    # Check if any results were found
    if [[ "$RESULT" =~ ^[0-9]+$ && "$RESULT" -ge 1 ]]; then
        return 0 # Email was sent
    else
        return 1 # Email not found
    fi
}

##############################
# Function: perform login
##############################
do_login() {
    echo "Logging in..."
    # Fetch the login page, set the referer header, and save cookies
    curl -c "$COOKIE_FILE" -s -e "$LOGIN_URL" "$LOGIN_URL" -o login_page.html

    # Extract the CSRF token from the login page
    CSRF_TOKEN=$(grep -oP 'name="csrfmiddlewaretoken" value="\K[^"]+' login_page.html)
    echo "CSRF Token: $CSRF_TOKEN"

    # Abort if CSRF token not found
    if [ -z "$CSRF_TOKEN" ]; then
        echo "CSRF token not found. Exiting."
        exit 1
    fi

    # Get user input for credentials
    read -p "Enter username: " USERNAME
    read -sp "Enter pass: " PASSWORD
    echo

    # Perform login, ensuring the referer header is set
    curl -b "$COOKIE_FILE" -c "$COOKIE_FILE" -s -e "$LOGIN_URL" \
        -d "username=$USERNAME" \
        -d "password=$PASSWORD" \
        -d "csrfmiddlewaretoken=$CSRF_TOKEN" \
        -X POST "$LOGIN_URL" \
        -o login_response.html

    # Optionally extract the session id from the cookie file
    SESSION_ID=$(grep 'sessionid' "$COOKIE_FILE" | awk '{print $NF}')
    echo "Session ID: $SESSION_ID"
}

##############################
# Function: check cookie validity
##############################
check_cookie() {
    echo "checking $COOKIE_FILE and https://archlinux.org/admin"
    HTTP_CODE=$(curl -L -b "$COOKIE_FILE" -s -o /dev/null -w "%{http_code}" "https://archlinux.org/admin")
    echo "HTTP status code from JSON endpoint: $HTTP_CODE" >>httpcode.log
    if [ "$HTTP_CODE" -ne 200 ]; then
        echo "Cookie is not valid. Re-authenticating..."
        do_login
    else
        echo "Cookie is valid."
    fi
}

##############################
# Function: validate an email
##############################
validate_email() {
    local email=$1
    # Basic regex validation – adjust as needed
    if [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

##############################
# fetch emails
##############################
fetch_emails() {
    MIRROR="$1"

    # If cookie file doesn't exist, perform login
    if [ ! -f "$COOKIE_FILE" ]; then
        do_login
    fi

    # Check cookie validity
    check_cookie >/dev/null 2>&1

    JSON_FILE="$MIRROR.json"

    # Fetch the JSON endpoint using the saved cookies
    curl -b "$COOKIE_FILE" -s "https://archlinux.org/mirrors/$MIRROR/json/" -o "$JSON_FILE"

    # Parse emails from the JSON
    ADMIN_EMAIL=$(jq -r '.admin_email' "$JSON_FILE")
    ALT_EMAIL=$(jq -r '.alternate_email' "$JSON_FILE")

    #echo "📨 Parsed emails: ADMIN=$ADMIN_EMAIL, ALT=$ALT_EMAIL"

    VALID_RECIPIENTS=""

    # Validate and build recipient list
    for email in "$ADMIN_EMAIL" "$ALT_EMAIL"; do
        if validate_email "$email"; then
            [[ -n "$VALID_RECIPIENTS" ]] && VALID_RECIPIENTS+=", $email" || VALID_RECIPIENTS="$email"
        fi
    done

    # If no valid recipients, return an error
    if [[ -z "$VALID_RECIPIENTS" ]]; then
        echo "⚠️ No valid email addresses found. Exiting."
        return 1
    fi

    MAILTO_URI="${VALID_RECIPIENTS}"
    echo "$MAILTO_URI" # ✅ Echo this so it's captured by command substitution
}
