#!/usr/bin/env bash

set -e

if [ -z "$1" ]; then
  echo "usage: $0 <channel_id> [profile]"
  echo "if channel_id = '?' - a list of channels will be presented"
  echo "profile is the TVH profile to use, for example: pass"
  exit
fi

if [ -z "$TVHAUTH" ]; then
  echo "export TVHAUTH with value <user>:<pass>"
  exit
fi

: ${tvh:=tvh}

grid="$(curl -sSu $TVHAUTH -d sort=svcname -d dir=ASC http://${tvh}:9981/api/mpegts/service/grid)"

if [ "$1" == "?" ]; then
  echo "$grid" | jq '.entries | sort_by(.lcn) | .[] | "\(.lcn): \(.provider) / \(.svcname) [\(if .dvb_servicetype == 1 then "SD" elif .dvb_servicetype == 2 then "Radio" elif .dvb_servicetype == 22 then "SD2" elif .dvb_servicetype == 25 then "HD" else .dvb_servicetype end)]"'
  exit
fi

channel_id=$1
profile=$2

service=$(echo "$grid" | jq -r '.entries[] | select(.lcn == '$channel_id') | .uuid')
url=$(curl -u $TVHAUTH -H 'User-Agent: VLC' http://${tvh}:9981/play/stream/service/$service 2> /dev/null | tail -n1)
url="${url:0: -1}${profile:+&profile=$profile}"

if [ -n "$print" ]; then
  echo -n ${url}
  exit
fi

mpv ${url}
