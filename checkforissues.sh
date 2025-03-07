# Configuration

source scripts.sh
echo "error here? mirrogroups"
mirrorgroups=$(jq -r '.urls[]
            | select(.active)
            | select( .score > 100  or .score == null or .delay > 259200  )
            | .details
            | capture("mirrors/(?<domain>[^/]+)")
            | .domain' all_mirrors.json | sort -u)

for mirror in $mirrorgroups; do
    echo "doing it for mirror $mirror"
    date
    MAILTO_URI=$(fetch_emails "$mirror") # check cookie ne pogleda ce res dela...
    date
    stats=$(get_problem_urls "$mirror")
    date
    echo "stats are: $stats"
    compose_email "$mirror" "$MAILTO_URI" "$stats"
    sleep 3
done

# get_problem_urls rackspace.com

# --- below not use
# for mirrordetails in $(jq '.urls[] | select( (.score > 100 and .active) or (.score == null and .active ) ) | .details' tier2.json); do
#     echo $mirrordetails | grep -oP 'mirrors/\K[^/]+'
# done #| sort -u

# for mirrordetails in $(jq '.urls[]' all_mirrors.json); do
#     echo $mirrordetails | grep -oP 'mirrors/\K[^/]+'
# done #| sort -u
#
# # this owrks
#

# vzet mirror iz public jsona
# pogledat statistiko za vse urlje
# izpisat urlje z problemi
# izluscit details in admin email (mogoce imeti posebi json za admin urlje)
# prpopat zraven z problem urlji
