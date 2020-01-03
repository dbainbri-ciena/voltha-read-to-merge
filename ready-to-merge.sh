#!/usr/bin/env bash

# Gerrit branch diff-er

set -eu -o pipefail

SUBJECT_LEN=${SUBJECT_LEN:-40}
VERIFIED=${VERIFIED:-all}
MERGEABLE=${MERGEABLE:-all}
SHORT=${SHORT:-no}
LINKS=${LINKS:-no}

VOPT=
if [ "$VERIFIED" == "yes" ]; then
    VOPT="label:verified+"
elif [ "$VERIFIED" == "no" ]; then
    VOPT="label:verified=reject+"
fi

HTTP=
if [ "$LINKS" == "yes" ]; then
    HTTP="http://gerrit.opencord.org/#/q/"
fi

REPOS="voltha-adtran-adapter \
    voltctl \
    voltha-lib-go \
    voltha-api-server \
    voltha-bal \
    bbsim \
    voltha-docs \
    voltha-go \
    voltha-helm-charts \
    voltha-omci \
    voltha-onos \
    voltha-openolt-adapter \
    voltha-openonu-adapter \
    voltha-protos \
    voltha-simolt-adapter \
    voltha-simonu-adapter \
    voltha-system-tests \
    pyvoltha"

if [ "$SHORT" == "no" ]; then
    FORMAT="%s|%s|%s|%s|%s|%s|%s|%.${SUBJECT_LEN}s\n"
else
    FORMAT="%s|%s|%s|%.${SUBJECT_LEN}s\n"
fi

FILTER=":"
for REPO in $REPOS; do
    FILTER="$FILTER$REPO:"
done

howlong() {
    local TODAY=$(date -u +%Y-%m-%d)
    local WHEN=$(echo $1 | awk '{print $1}')

    local T_Y=$(echo $TODAY | cut -d- -f1)
    local T_M=$(echo $TODAY | cut -d- -f2 | sed -e 's/^0//g')
    local T_D=$(echo $TODAY | cut -d- -f3 | sed -e 's/^0//g')

    local W_Y=$(echo $WHEN | cut -d- -f1)
    local W_M=$(echo $WHEN | cut -d- -f2 | sed -e 's/^0//g')
    local W_D=$(echo $WHEN | cut -d- -f3 | sed -e 's/^0//g')

    python -c "from datetime import date; print (date($T_Y,$T_M,$T_D)-date($W_Y,$W_M,$W_D)).days"
}

#        | sed 1,1d | jq -r '.[] | .project+"|"+.owner.email+"|"+.branch+"|"+.change_id+"|"+(.mergeable|tostring)+"|"+.updated+"|"+.subject' \
if [ "$SHORT" == "no" ]; then
    TITLES="REPO OWNER BRANCH MERGEABLE REVIEWS CHANGE_ID UPDATED SUBJECT"
else
    TITLES="REPO CHANGE_ID UPDATED SUBJECT"
fi
(printf "$FORMAT" $TITLES &&
    for LINE in $(curl -sSL \
        "http://gerrit.opencord.org/changes/?q=${VOPT}is:open&o=DETAILED_ACCOUNTS" \
        | sed 1,1d | jq -r '.[] | .id+"|"+.project+"|"+.owner.email+"|"+.branch+"|"+(.mergeable|tostring)+"|"+.change_id+"|"+.updated+"|"+.subject' \
        | sed -e 's/  */__SPACE__/g'); do
        ID=$(echo $LINE | cut -d\| -f1)
        REPO=$(echo $LINE | cut -d\| -f2)
        OWNER=$(echo $LINE | cut -d\| -f3)
        if [ -z "$OWNER" ]; then
            OWNER="unknown"
        fi
        if [ $(echo "$FILTER" | grep -c ":$REPO:") -eq 0 ]; then
            continue
        fi
        BRANCH=$(echo $LINE | cut -d\| -f4)
        case "$BRANCH" in
            master|voltha-2.1)
                ;;
            *)
                continue
        esac
        IS_MERGEABLE=$(echo $LINE | cut -d\| -f5)
        if [ "$MERGEABLE" == "yes" -a "$IS_MERGEABLE" != "true" ]; then
            continue
        elif [ "$MERGEABLE" == "no" -a "$IS_MERGEABLE" != "false" ]; then
            continue
        fi
        CHANGE_ID=$(echo $LINE | cut -d\| -f6)
        UPDATED="$(howlong $(echo $LINE | cut -d\| -f7 | sed -e 's/__SPACE__/ /g')) days ago"

        SUBJECT=$(echo $LINE | cut -d\| -f8)
        REVIEWS=
        for V in $(curl -sSL http://gerrit.opencord.org/changes/$ID/detail | sed -e 1,1d | jq  '.labels."Code-Review" | select(.all != null) | .all[] | select(.value != 0) | .value'); do
            if [ $V -gt 0 ]; then
                REVIEWS="$REVIEWS+$V, "
            elif [ $V -lt 0 ]; then
                REVIEWS="$REVIEWS$V, "
            fi
        done
        REVIEWS="[$(echo $REVIEWS | sed -e 's/, *$//g')]"
        if [ "$SHORT" == "no" ]; then
            printf "$FORMAT" "$REPO" "$OWNER" "$BRANCH" "$IS_MERGEABLE" "$REVIEWS" "$HTTP$CHANGE_ID" "$UPDATED" "$(echo $SUBJECT | sed -e 's/__SPACE__/ /g')"
        else
            printf "$FORMAT" "$REPO" "$HTTP$CHANGE_ID" "$UPDATED" "$(echo $SUBJECT | sed -e 's/__SPACE__/ /g')"
        fi
    done) | column -tx '-s\|' | grep -vi "WIP" | grep -vi "T MERGE" | grep -vi "draft"
