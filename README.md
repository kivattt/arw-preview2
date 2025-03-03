## This is a work-in-progress project

## Supported image files
- .ARW by Sony a6000
- .CR3 by Canon EOS R50

Raw image files created by other camera models have not been tested.

## Building
Install [Odin](https://odin-lang.org/)
```
odin build . -o:speed
```

## Running
```
./arw-preview2 example.ARW
# or
./arw-preview2 example.CR3
```

## Todo
- Right click -> Copy to clipboard
- Multiple files
- Timing outputs in --verbose

The included [Inter](fonts/Inter/Inter-Regular.ttf) font is licensed under the OFL-1.1. A copy of this license is included in [fonts/Inter/LICENSE.txt](fonts/Inter/LICENSE.txt)
