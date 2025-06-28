# Configuration
rm result.log
rm emailsent.log
source scripts.sh
mirrorgroups=$(jq -r '.urls[]
            | select(.active)
            | select( .score > 100  or .score == null or .delay > 259200  )
            | .details
            | capture("mirrors/(?<domain>[^/]+)")
            | .domain' all_mirrors.json | sort -u)

DB_PATH="/home/arun/.thunderbird/zwzshc74.default-release/global-messages-db.sqlite"
cp "$DB_PATH" global-messages-db.copy.sqlite
for mirror in $mirrorgroups; do
    echo "📌 Processing mirror: $mirror"

    # Call fetch_emails and capture return value separately
    MAILTO_URI=$(fetch_emails "$mirror")

    # Loop through emails to check if a message was already sent
    IFS=","
    for email in $MAILTO_URI; do
        email=$(echo "$email" | xargs)
        echo "checking for email: $email"

        if check_if_sent "$email"; then
            echo "✅ Email already sent to: $email" >>emailsent.log
            continue
        else
            echo "📧 Mailto URI: $MAILTO_URI"
            stats=$(get_problem_urls "$mirror")
            echo "📊 Mirror Stats: $stats"
            compose_email "$mirror" "$MAILTO_URI" "$stats"
            sleep 3
            break 1
        fi
    done

done
