#!/usr/bin/env bash

# Required tools:
# ffmpeg
# gifsicle
# imagemagick

function printHelpAndExit {
cat <<EOF
Usage:
  gifify [options] filename
Version:   2.0.0

Convert videos into GIFs.

Options: (all optional)
  c CROP:     The x and y crops, from the top left of the image, i.e. 640:480
  o OUTPUT:   The basename of the file to be output (defaults to input basename)
  r FPS:      Output at this (frame)rate (default 10)
  s SPEED:    Output using this speed modifier (default 1)
              NOTE: GIFs max out at 100fps depending on platform. For consistency,
              ensure that FPSxSPEED is not > ~60!
  p SCALE:    Rescale the output, e.g. 320:240
  l LOOP:     Set loop extension to N iterations (default 0 - forever).
  F           Fast mode produces results faster, at lower quality
  x:          Remove the original file

Example:
  gifify -c 240:80 -o my-gif -x my-movie.mov

EOF
exit $1
}

# Initialize variables
fps=12
speed=1
loop=0
fast=0

OPTERR=0

while getopts "c:o:p:r:s:l:xFh" opt; do
  case $opt in
    c) crop=$OPTARG;;
    h) printHelpAndExit 0;;
    o) output=$OPTARG;;
    p) scale=$OPTARG;;
    r) fps=$OPTARG;;
    s) speed=$OPTARG;;
    l) loop=$OPTARG;;
    F) fast=1;;
    x) cleanup=1;;
    *) printHelpAndExit 1;;
  esac
done

shift $(( OPTIND - 1 ))

filename="$1"

if [ -z "$output" ]; then
  output="${filename}.gif"
fi

if [ -z "$filename" ]; then printHelpAndExit 1; fi

# Video filters (scan / crop)
if [ $crop ]; then
  crop="crop=${crop}:0:0"
else
  crop=
fi

# Add scale filter
# @link https://www.ffmpeg.org/ffmpeg-scaler.html#toc-Scaler-Options
if [ $scale ]; then
  scale="scale=${scale}:sws_dither=ed"
else
  scale=
fi

if [ $scale ] || [ $crop ]; then
  filter="${scale}${crop}"
else
  filter=
fi

# Looping with convert 0 = forever, N = N iterations
# Looping with gifsicle 0 = forever, N = N+1 iterations, --no-loopcount = disable looping

# -delay uses time per tick (a tick defaults to 1/100 of a second)
# so 60fps == -delay 1.666666 which is rounded to 2 because convert
# apparently stores this as an integer. To animate faster than 60fps,
# you must drop frames, meaning you must specify a lower -r. This is
# due to the GIF format as well as GIF renderers that cap frame delays
# < 3 to 3 or sometimes 10. Source:
# @link http://humpy77.deviantart.com/journal/Frame-Delay-Times-for-Animated-GIFs-214150546
# delay=$(bc -l <<< "100/$fps/$speed")
delay=$(( 100 / $fps / $speed ))

# Use this method to conserve memory (slower)
# temp=$(mktemp /tmp/tempfile.XXXXXXXXX)
# ffmpeg -loglevel panic -i $filename $filter -r $fps -f image2pipe -vcodec ppm - >> $temp
# cat $temp | convert +dither -layers Optimize -delay $delay - ${output}.gif

if [ $fast -ne 1 ]; then
  # SLOW/BETTER
  # Use images, piped through convert to generate output
  # Dithering will likely improve quality at the expense of filesize
  # `convert -list dither` to get a list of supported dither methods
  vfs=
  [ -n "$filter" ] && vfs=(-vf "${filter}")
  ffmpeg -loglevel panic -i "$filename" ${vfs[@]} -r $fps -f image2pipe -vcodec ppm - | convert -layers Optimize -loop $loop -delay $delay - gif:- | gifsicle --optimize=3 - > "$output"
else
  # gifsicle accepts int values for delay
  delay=$(( 100 / $fps / $speed ))

  # SLOWEST/BEST
  # Generate a palette to improve quality
  # @link http://blog.pkh.me/p/21-high-quality-gif-with-ffmpeg.html
  palette=$(mktemp /tmp/palette.XXXXXXXXX.png)
  ffmpeg -loglevel panic -i "$filename" -vf "${filter},palettegen" -y "$palette"
  ffmpeg -loglevel panic -i "$filename" -i "$palette" -lavfi "${filter} [x]; [x][1:v] paletteuse" -r $fps -f gif - | gifsicle --optimize=3 --delay=${delay} - > "$output"
  rm "$palette"

  # FAST/GOOD
  # Note: `-pix_fmt rgb24` may produce poor results
  # ffmpeg -loglevel panic -i "$filename" -vf "$filter" -r $fps -f gif - | gifsicle --optimize=3 --delay=${delay} - > "$output"
fi

if [ $cleanup ]; then
  rm "$filename"
fi
