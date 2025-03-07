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

    if [ $? == 0 ] && [ ! -e "$mirror.composed" ]; then
        touch "$mirror".composed
        echo "$2" >>"$mirror".composed
        echo "$3" >>"$mirror".composed
    else
        echo "Mirror $mirror already messaged"
        return
    fi

    thunderbird -compose "from='pitastrudl@archlinux.org',subject='Problem with $1 Arch Linux mirror',to='$2',body='Hi,

    We have noticed that your Arch Linux mirror $1 is currently not functional. If the issue persists, the mirror or URLs may eventually be disabled. Please investigate the matter at your earliest convenience and let us know once it has been resolved, thank you very much.

    Below are some values from the Arch Linux website https://archlinux.org/mirrors/status/ where you will find some more information about the values as well.

    $3

    Best regards,
    Arun
    Arch Linux mirror team
                '" &

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
    #1 mirror name
    # If cookie file doesn't exist, perform login
    if [ ! -f "$COOKIE_FILE" ]; then
        do_login
    fi

    # Check cookie validity
    check_cookie >/dev/null 2>&1 # have to recreate cookie after some time
    JSON_FILE="$1"".json"
    # Fetch the JSON endpoint using the saved cookies
    curl -b "$COOKIE_FILE" -s "https://archlinux.org/mirrors/$1/json/" -o "$JSON_FILE"
    #echo "JSON response saved to $JSON_FILE"

    # Parse emails from the JSON
    ADMIN_EMAIL=$(jq -r '.admin_email' "$JSON_FILE")
    ALT_EMAIL=$(jq -r '.alternate_email' "$JSON_FILE")

    # echo "Parsed emails:"
    # echo "  Admin:     $ADMIN_EMAIL"
    # echo "  Alternate: $ALT_EMAIL"

    VALID_RECIPIENTS=""

    for email in "$ADMIN_EMAIL" "$ALT_EMAIL"; do
        if validate_email "$email"; then
            [[ -n "$VALID_RECIPIENTS" ]] && VALID_RECIPIENTS+=", $email" || VALID_RECIPIENTS="$email"
        fi
    done

    [[ -z "$VALID_RECIPIENTS" ]] && {
        echo "No valid email addresses provided. Exiting."
        exit 1
    }

    MAILTO_URI="to:${VALID_RECIPIENTS}"
    echo "Mail addresses: $MAILTO_URI"
}
