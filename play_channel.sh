#!/usr/bin/env bash

set -e

if [ -z "$1" ]; then
  echo "usage: $0 <channel_id>"
  echo "if channel_id = '?' - a list of channels will be presented"
  exit
fi

if [ -z "$TVHAUTH" ]; then
  echo "export TVHAUTH with value <user>:<pass>"
  exit
fi

: ${tvh:=tvh}

if [ "$1" == "?" ]; then
	curl -u $TVHAUTH -d sort=svcname -d dir=ASC http://${tvh}:9981/api/mpegts/service/grid 2> /dev/null | sed 's/[^}]*"lcn": \([^,]*\),[^}]*"svcname": "\([^"]*\)","provider": "\([^"]*\)"[^}]*"dvb_servicetype": \([^,]*\),[^}]*}/\1\: \3 \/ \2 [st\4]\n/g;s/st1/SD/g;s/st25/HD/g;s/st22/SD2/g;s/st2/Radio/g' | head -n-1 | sort -n
  exit
fi

channel_id=$1

service=$(curl -u $TVHAUTH -d sort=svcname -d dir=ASC http://${tvh}:9981/api/mpegts/service/grid 2> /dev/null | sed 's/.*{"uuid": "\([^"]*\)"[^}]*"lcn": '$1',.*/\1/')
url=$(curl -u $TVHAUTH -H 'User-Agent: VLC' http://${tvh}:9981/play/stream/service/$service 2> /dev/null | tail -n1)

if [ -n "$print" ]; then
  echo -n ${url:0: -1}
  exit
fi

mpv ${url:0: -1}
