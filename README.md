# tvhscripts
Scripts for TVHeadend (playing, streaming, etc...)

Export TVHAUTH with username and password:

```
export TVHAUTH=user:pass
```

Then view channels with, for example:
```
tvh=localhost ./play_channel.sh ?
```

Then play locally with, for example:
```
tvh=localhost ./play_channel.sh 70
```

Create a webpage with hls streaming options:
```
tvh=localhost ./hls_channel.sh 70
```

Create a webpage with a dash stream:
```
tvh=localhost ./stream_channel.sh 70
```

For `hls_channel` and `stream_channel`, you can also specify different encoding options as a second parameter. For example:
```
tvh=localhost ./hls_channel.sh 70 fullhd hd sd
```

Available options are:
- `fullhd`
- `hd`
- `sd`
- `fullhd_vaapi`
- `hd_vaapi`
- `sd_vaapi`
- `fullhd_nvenc`
- `hd_nvenc`
- `sd_nvenc`
- `fullhd_hevc_nvenc`
- `hd_hevc_nvenc`
- `sd_hevc_nvenc`
- `fullhd_cuvid`
- `hd_cuvid`
- `sd_cuvid`
- `fullhd_hevc_cuvid`
- `hd_hevc_cuvid`
- `sd_hevc_cuvid`
