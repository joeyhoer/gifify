#!/usr/bin/env bash

# Set global variables
PROGNAME=$(basename "$0")
VERSION='1.0.0'

##
# Join a list with a seperator
#
# @param 1  Seperator
# @param 2+ Items to join
##
join_by() { local IFS="$1"; shift; echo "$*"; }

##
# Check for a dependancy
#
# @param 1 Command to check
##
dependancy() {
  hash "$1" &>/dev/null || error "$1 must be installed"
}

##
# Throw an error
#
# @param 1 Command to check
# @param 2 [1] Error status. If '0', will not exit
##
error() {
  echo -e "Error: ${1:-"Unknown Error"}" >&2
  if [[ ! "$2" == 0 ]]; then
    [[ -n "$2" ]] && exit "$2" || exit 1
  fi
}

##
# Print help menu
#
# @param 1 exit code
##
print_help() {
cat <<EOF
Usage:     $PROGNAME [options] input-file
Version:   $VERSION

Options: (all optional)
  -c value  Crop the input
  -C        Conserve memory by writing frames to disk (slower)
  -d value  Directon (normal, reverse, alternate) [default: normal]
  -l value  Set loop extension to N iterations (default 0 - forever).
  -o value  The output file
  -p value  Scale the output, e.g. 320:240
  -q value  Quality. The higher the quality, the longer it takes to generate
  -r value  Set the output framerate (default 10)
  -s value  Set the speed modifier (default 1)
            NOTE: GIFs max out at 100fps depending on platform. For consistency,
            ensure that FPSxSPEED is not > ~60!
  -S value  Set start time (default 0)
  -t value  Set duration (default full video)
  -v        Print version

Example:
  $PROGNAME -c 240:80 -o sample.gif sample.mov
EOF
exit $1
}

################################################################################

# Check dependacies
dependancy ffmpeg
dependancy magick
dependancy gifsicle

# Initialize variables
fps=12
speed=1
quality=2
useio=0
loop=0
OPTERR=0
filter=
scale=
crop=
start=
duration=

# Get options
while getopts "c:d:o:p:r:s:S:t:l:q:Chv" opt; do
  case $opt in
    c) crop=$OPTARG;;
    C) useio=1;;
    d) direction=$OPTARG;;
    h) print_help 0;;
    l) loop=$OPTARG;;
    o) outfile=$OPTARG;;
    p) scale=$OPTARG;;
    q) quality=$OPTARG;;
    r) fps=$OPTARG;;
    s) speed=$OPTARG;;
    S) start=$OPTARG;;
    t) duration=$OPTARG;;
    v)
      echo "$VERSION"
      exit 0
      ;;
    *) print_help 1;;
  esac
done

shift $(( OPTIND - 1 ))

infile="$1"
if [ -z "$outfile" ]; then
  outfile="$2"
fi

if [ -z "$outfile" ]; then
  outfile="${infile}.gif"
fi

if [ -z "$infile" ]; then print_help 1; fi


# Video filters (scan / crop)
if [ $crop ]; then
  crop="crop=${crop}"
fi

# Add scale filter
# @link https://www.ffmpeg.org/ffmpeg-scaler.html#toc-Scaler-Options
if [ $scale ]; then
  scale="scale=${scale}:flags=lanczos"
fi

if [ $crop ] || [ $scale ]; then
  filter="$(join_by , $crop $scale)"
fi

# Direction options (for use with magick)
direction_opt=
if [[ $direction == "reverse" ]]; then
  direction_opt="-coalesce -reverse"
elif [[ $direction == "alternate" ]]; then
  direction_opt="-coalesce -duplicate 1,-2-1"
fi

# Duration opt (for use with ffmpeg)
start_opt=
if [ $start ]; then
  start_opt="-ss ${start}"
fi

# Duration opt (for use with ffmpeg)
duration_opt=
if [ $duration ]; then
  duration_opt="-t ${duration}"
fi

# -delay uses time per tick (a tick defaults to 1/100 of a second)
# so 60fps == -delay 1.666666 which is rounded to 2 because magick
# apparently stores this as an integer. To animate faster than 60fps,
# you must drop frames, meaning you must specify a lower -r. This is
# due to the GIF format as well as GIF renderers that cap frame delays
# < 3 to 3 or sometimes 10. Source:
# @link http://humpy77.deviantart.com/journal/Frame-Delay-Times-for-Animated-GIFs-214150546
delay=$(bc -l <<< "100/$fps/$speed")

if [ $useio -ne 1 ]; then
  if [ $quality == 1 ]; then
    # SLOW/BETTER
    # Use images, piped through magick to generate output
    # Dithering will likely improve quality at the expense of filesize
    # `magick -list dither` to get a list of supported dither methods
    [[ $filter ]] && filter_opt="-vf ${filter}"
    ffmpeg -loglevel panic $start_opt $duration_opt -i "$infile" $filter_opt -r $fps -f image2pipe -vcodec ppm - | \
      magick - $direction_opt -layers Optimize -loop $loop -delay $delay gif:- | \
      gifsicle --optimize=3 - -o "$outfile"

  elif [ $quality -ge 2 ]; then
    # SLOWEST/BEST
    # Generate a palette to improve quality
    # May result in smaller files
    # May result in "swarming"
    # @link http://blog.pkh.me/p/21-high-quality-gif-with-ffmpeg.html
    filter_gen="palettegen"
    filter_use="paletteuse"
    if [[ $filter ]]; then
      filter_gen="$(join_by , ${filter} palettegen)"
      filter_use="${filter}[x];[x][1:v]paletteuse"
    fi

    palette=$(ffmpeg -loglevel panic $start_opt $duration_opt -i "$infile" -vf $filter_gen -f image2 - | base64)
    ffmpeg -loglevel panic $start_opt $duration_opt -i "$infile" -i  <(base64 --decode <<< "$palette") \
      -lavfi $filter_use -r $fps -f gif - | \
      magick - $direction_opt -layers Optimize -loop $loop -delay $delay gif:- | \
      gifsicle --optimize=3 - -o "$outfile"

  elif [ $quality -le 0 ]; then
    # FAST/GOOD
    # Note: `-pix_fmt rgb24` may produce poor results
        # gifsicle accepts int values for delay
    # Ditering with -sws_dither x_dither may have some effect on output
    delay=$(( 100 / $fps / $speed ))

    # Looping from 1 to 65535 with:
    # program    infinite   iterations   no loop
    # magick     0          N            1
    # ffmpeg     0          N+1          -1
    # gifsicle   0          N+1          --no-loopcount

    # gifsicle loop options
    # if [[ $loop -eq 1 ]]; then
    #   loop_opt="--no-loopcount"
    # elif [[ $loop -gt 1 ]]; then
    #   loop_opt="--loopcount=$(( $loop - 1 ))"
    # fi

    # ffmpeg loop options
    if [[ $loop -eq 1 ]]; then
      loop="-1"
    elif [[ $loop -gt 1 ]]; then
      loop="$(( $loop - 1 ))"
    fi

    [[ $filter ]] && filter_opt="-vf ${filter}"
    data=$(ffmpeg -y -loglevel panic $start_opt $duration_opt -i "$infile" $filter_opt -r $fps -loop $loop -f gif - | base64)

    if [[ $direction == "reverse" ]]; then
      # Reverse
      gifsicle -U <(base64 --decode <<< "$data") --delay=${delay} --optimize=3 "#-1-0" -o "$outfile"
    elif [[ $direction == "alternate" ]]; then
      # Alternate
      gifsicle -U <(base64 --decode <<< "$data") "#-2-1" -o - | \
        gifsicle --delay=${delay} --optimize=3 <(base64 --decode <<< "$data") --append - -o "$outfile"
    else
      # Normal
      gifsicle --delay=${delay} --optimize=3 <(base64 --decode <<< "$data") -o "$outfile"
    fi

  fi
else
  [[ $filter ]] && filter_opt="-vf ${filter}"
  temp=$(mktemp "/tmp/${PROGNAME}.XXXXXXXXX")
  ffmpeg -loglevel panic $start_opt $duration_opt -i "$infile" $filter_opt -r $fps -f image2pipe -vcodec ppm - >> "$temp"
  magick $direction_opt -layers Optimize -delay $delay -loop $loop "$temp" gif:- | \
    gifsicle --optimize=3 - -o "$outfile"
  rm "$temp"
fi
