#!/usr/bin/env bash

set -e

if [ -z "$1" ]; then
  echo "usage: $0 <channel_id> [<quality> ...]"
  echo "if channel_id = '?' - a list of channels will be presented"
  echo "quality - sd, hd or fullhd. Each 'quality' value will create a new stream"
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

service=$(echo "$grid" | jq -r '.entries[] | select(.lcn == '$channel_id') | .uuid')
url=$(curl -u $TVHAUTH -H 'User-Agent: VLC' http://${tvh}:9981/play/stream/service/$service 2> /dev/null | tail -n1)
url="${url:0: -1}&profile=${profile:-pass}"

if [ -n "$print" ]; then
  echo -n ${url}
  exit
fi

if [ -z "$2" ]; then
  outputs=(hd)
else
  shift

  outputs=()
  while (( "$#" )); do
    outputs+=("$1")
     shift
  done
fi

sw=0
vaapi=0
cuvid=0

for output in ${outputs[@]}; do
  if [ "${output: -6}" == "_vaapi" ]; then
    if [ "${vaapi}" -eq 0 ]; then
      inputs+=("vaapi")
    fi
    ((vaapi++)) || true
  elif [ "${output: -6}" == "_cuvid" ]; then
    if [ "${cuvid}" -eq 0 ]; then
      inputs+=("cuvid")
    fi
    ((cuvid++)) || true
  else
    if [ "$sw" -eq 0 ]; then
      inputs+=("sw")
    fi
    ((sw++)) || true
  fi
done

i=0
for input in ${inputs[@]}; do
  if [ "${input}" == "sw" ]; then
    decode=
    filter="yadif"
  elif [ "${input}" == "vaapi" ]; then
    decode="-hwaccel vaapi -vaapi_device /dev/dri/renderD128 -hwaccel_output_format vaapi"
    filter="deinterlace_vaapi=mode=4"
  elif [ "${input}" == "cuvid" ]; then
    decode="-hwaccel cuvid -c:v h264_cuvid -deint adaptive -drop_second_field 1"
    filter=
  fi

  name="${input}"
  if [ ${!input} -gt 1 ]; then
    if [ -n "${filter}" ]; then
      fsep=","
    else
      fsep=
    fi

    filter="${filter}${fsep}split=${!input}"
  fi

  filter="[${i}:v]${filter}"

  if [ "${input}" == "sw" ]; then
    sw_filter="${filter}"
    sw_achannel=${i}
  elif [ "${input}" == "vaapi" ]; then
    vaapi_filter="${filter}"
    vaapi_achannel=${i}
  elif [ "${input}" == "cuvid" ]; then
    cuvid_filter="${filter}"
    cuvid_achannel=${i}
  fi

  ffinput="${ffinput}${decode} -i ${url} "
  audio="${audio} -map ${i}:a -c:${i} aac -ac 2"
  if [ -n "${onestream}" ]; then
    var_stream_map="${var_stream_map} a:$i,agroup:audio_$i"
  fi
  ((i++)) || true
done

achannels=${i}
subtiles="-sn"
common="-keyint_min 125 -g 125"
format="-hls_time 5 -hls_list_size $((60*60*2)) ${segment_type:+-hls_segment_type} ${segment_type} ${ts_options:+-hls_ts_options} ${ts_options}"

if [ -n "${onestream}" ]; then
  filename="tv_hls.m3u8"
  format="${format} -f hls -master_pl_name ${filename} -var_stream_map"
else
  format="${format} -f tee"
fi

rm -f ffmpeg.log tv_*.{ts,m3u8,m4s} index.html init*.mp4

i=${achannels}
for output in ${outputs[@]}; do
  fullhd="-c:${i} h264 -preset:${i} faster -tune:${i} zerolatency -crf:${i} 31 -b:${i} 1800k -maxrate:${i} 2610k -bufsize:${i} 5220k -s:${i} 1920x1080"
  hd="-c:${i} h264 -preset:${i} medium -tune:${i} zerolatency -crf:${i} 32 -b:${i} 1024k -maxrate:${i} 1485k -bufsize:${i} 2970k -s:${i} 1280x720"
  sd="-c:${i} h264 -preset:${i} slow -tune:${i} zerolatency -crf:${i} 33 -b:${i} 750k -maxrate:${i} 1088k -bufsize:${i} 2176k -s:${i} 1024x576"

  fullhd_vaapi="-c:${i} h264_vaapi -compression_level:${i} 1 -b:${i} 2610k -maxrate:${i} 2610k -bufsize:${i} 5220k"
  hd_vaapi="-c:${i} h264_vaapi -compression_level:${i} 1 -b:${i} 1485k -maxrate:${i} 1485k -bufsize:${i} 2970k"
  sd_vaapi="-c:${i} h264_vaapi -compression_level:${i} 1 -b:${i} 1088k -maxrate:${i} 1088k -bufsize:${i} 2176k"

  fullhd_nvenc="-c:${i} h264_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 1800k -maxrate:${i} 2610k -bufsize:${i} 5220k -s:${i} 1920x1080"
  hd_nvenc="-c:${i} h264_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 1024k -maxrate:${i} 1485k -bufsize:${i} 2970k -s:${i} 1280x720"
  sd_nvenc="-c:${i} h264_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 750k -maxrate:${i} 1088k -bufsize:${i} 2176k -s:${i} 1024x576"

  fullhd_hevc_nvenc="-c:${i} hevc_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 1800k -maxrate:${i} 2610k -bufsize:${i} 5220k -s:${i} 1920x1080"
  hd_hevc_nvenc="-c:${i} hevc_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 1024k -maxrate:${i} 1485k -bufsize:${i} 2970k -s:${i} 1280x720"
  sd_hevc_nvenc="-c:${i} hevc_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 750k -maxrate:${i} 1088k -bufsize:${i} 2176k -s:${i} 1024x576"

  fullhd_cuvid="-c:${i} h264_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 1800k -maxrate:${i} 2610k -bufsize:${i} 5220k"
  hd_cuvid="-c:${i} h264_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 1024k -maxrate:${i} 1485k -bufsize:${i} 2970k"
  sd_cuvid="-c:${i} h264_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 750k -maxrate:${i} 1088k -bufsize:${i} 2176k"

  fullhd_hevc_cuvid="-c:${i} hevc_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 1800k -maxrate:${i} 2610k -bufsize:${i} 5220k"
  hd_hevc_cuvid="-c:${i} hevc_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 1024k -maxrate:${i} 1485k -bufsize:${i} 2970k"
  sd_hevc_cuvid="-c:${i} hevc_nvenc -preset:${i} llhq -zerolatency:${i} 1 -cq:${i} 0 -b:${i} 750k -maxrate:${i} 1088k -bufsize:${i} 2176k"

  if [ "${output: -6}" == "_vaapi" ]; then
    input=vaapi
  elif [ "${output: -6}" == "_cuvid" ]; then
    input=cuvid
  else
    input=sw
  fi

  if [ "${input}" == "vaapi" ]; then
    fullhd_vaapi_scale="w=1920:h=1080"
    hd_vaapi_scale="w=1280:h=720"
    sd_vaapi_scale="w=1024:h=576"

    scale="${output}_scale"

    if [ ${vaapi} -gt 1 ]; then
      vaapi_filter="${vaapi_filter}[va${i}]"
      stream_filters="${stream_filters};[va${i}]scale_vaapi=${!scale}[vaapi$i]"
    else
      vaapi_filter="${vaapi_filter},scale_vaapi=${!scale}[vaapi$i]"
    fi

    a=${vaapi_achannel}
  elif [ "${input}" == "cuvid" ]; then
    fullhd_cuvid_scale="w=1920:h=1080"
    hd_cuvid_scale="w=1280:h=720"
    sd_cuvid_scale="w=1024:h=576"

    fullhd_hevc_cuvid_scale="${fullhd_cuvid_scale}"
    hd_hevc_cuvid_scale="${hd_cuvid_scale}"
    sd_hevc_cuvid_scale="${sd_hevc_cuvid_scale}"

    scale="${output}_scale"

    if [ ${cuvid} -gt 1 ]; then
      cuvid_filter="${cuvid_filter}[cu${i}]"
      stream_filters="${stream_filters};[cu${i}]scale_cuda=${!scale}[cuvid$i]"
    else
      cuvid_filter="${cuvid_filter}scale_cuda=${!scale}[cuvid$i]"
    fi

    a=${cuvid_achannel}
  else
    sw_filter="${sw_filter}[sw${i}]"
    a=${sw_achannel}
  fi

  if [ -n "${onestream}" ]; then
    var_stream_map="${var_stream_map} v:$((i-achannels)),agroup:audio_$a"
    if [ ${i} -eq ${achannels} ]; then
      echo "<a href=\"${filename}\">TV</a><br>"
      filename="${filename:0: -5}_%v.m3u8"
    fi
  else
    fn="tv_hls_${output}.m3u8"
    echo "<a href=\"${fn}\">${output}</a><br>"
    filename="${filename}${sep}[select=\'$i,$a\':f=hls]${fn}"
    sep="|"
  fi

  stream_data="${stream_data} -map [${input}$i] ${!output}"

  ((i++)) || true
done > index.html

filter_complex="-filter_complex "

for input in ${inputs[@]}; do
  if [ "${input}" == "sw" ]; then
    filter="${sw_filter}"
  elif [ "${input}" == "vaapi" ]; then
    filter="${vaapi_filter}"
  elif [ "${input}" == "cuvid" ]; then
    filter="${cuvid_filter}"
  fi
  filter_complex="${filter_complex}${fc_sep}${filter}"
  fc_sep=";"
done

filter_complex="${filter_complex}${stream_filters}"

cmd="${ffmpeg:-ffmpeg} -loglevel ${loglevel:-error} ${ffinput} "\
"${subtitles} ${audio} ${common} ${filter_complex} "\
"${stream_data} ${format}"

if [ -n "${printcmd}" ]; then
  echo $cmd ${var_stream_map:+"${var_stream_map}"} $filename
  exit
fi

if [ -n "${fg}" ]; then
  $cmd ${var_stream_map:+"${var_stream_map}"} $filename
  exit
fi

$cmd ${var_stream_map:+"${var_stream_map}"} $filename &> ffmpeg.log &
echo Starting stream...

sleep ${sleep:-10}

python - 8080 << END &
import BaseHTTPServer
from SocketServer import ThreadingMixIn
from SimpleHTTPServer import SimpleHTTPRequestHandler

class ThreadedHTTPServer(ThreadingMixIn, BaseHTTPServer.HTTPServer):
  pass

BaseHTTPServer.test(SimpleHTTPRequestHandler, ThreadedHTTPServer, "HTTP/1.1")
END

trap 'kill $(jobs -rp); wait $(jobs -rp) 2> /dev/null || true; rm -f ffmpeg.log tv_*.{ts,m3u8,m4s} index.html init*.mp4' INT

wait $(jobs -rp) 2> /dev/null || true

rm -f ffmpeg.log tv_*.{ts,m3u8,m4s} index.html init*.mp4
