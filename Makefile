.PHONY: all clean view

view: image.ppm
	@feh --zoom 300 image.ppm

all: image.ppm

image.ppm: src/main.zig
	zig build run >image.ppm

clean:
	rm -f image.ppm
