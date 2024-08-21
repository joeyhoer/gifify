# gifify

gifify is a shell script for converting screen recordings into GIFs that can be conveniently embedded into a number of services.

## Installation

```sh
brew install gifify
```

## Usage

```sh
Usage:     gifify [options] input-file

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
```

### Examples

Given a file `recording.mov`:

#### Convert it into example.mov.gif:

```sh
gifify example.mov
```

#### Convert it into `gif.gif`

```sh
gifify -o gif.gif example.mov
```

#### Convert it, cropping the top left corner:

```sh
gifify -c 100:100 example.mov
```

#### Convert it, and output at 60 frames per second:

```sh
gifify -r 60 example.mov
```

#### Convert it, and output at 30 frames per second at 2x speed:

```sh
gifify -r 30 -s 2 example.mov
```

#### Convert it, and output at 10 frames per second at 6x speed:

```sh
gifify -s 6 example.mov
```

## Regarding framerates:

GIF renderers typically cap the framerate somewhere between 60 and 100 frames per second. If you choose to change the framerate or playback speed of your GIFs, ensure your framerates do not exceed 60 frames per second to ensure your GIFs play consistently. An easy way to compute this is to ensure that FPS  (`-r`) x SPEED (`-s`) is not greater than 60.

## License

MIT (See [LICENSE][1])

[1]: https://raw.github.com/jclem/gifify/master/LICENSE
