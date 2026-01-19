# Makefile for SDL2 render tests
# Usage: make all

CC = gcc
CFLAGS = -Wall -O2 $(shell sdl2-config --cflags)
LIBS = $(shell sdl2-config --libs) -lm
LIBS_TTF = $(LIBS) -lSDL2_ttf -lSDL2_image
LIBS_EGL = -lEGL -lGLESv2 -lgbm

all: render_test render_test_ttf check_renderer

render_test: render_test.c
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)
	@echo "✅ Built: $@"

render_test_ttf: render_test_ttf.c
	$(CC) $(CFLAGS) $< -o $@ $(LIBS_TTF)
	@echo "✅ Built: $@"

check_renderer: check_renderer.c
	$(CC) $(CFLAGS) $< -o $@ $(LIBS)
	@echo "✅ Built: $@"

clean:
	rm -f render_test render_test_ttf check_renderer
	@echo "🧹 Cleaned"

test: render_test
	@echo "Running basic render test (no text)..."
	SDL_VIDEODRIVER=kmsdrm ./render_test

test_ttf: render_test_ttf
	@echo "Running TTF render test (with text + images)..."
	SDL_VIDEODRIVER=kmsdrm ./render_test_ttf

check: check_renderer
	@echo "Checking OpenGL ES renderer..."
	./check_renderer

diagnose:
	@echo "Running full diagnostic..."
	@./check_gl_renderer.sh

.PHONY: all clean test test_ttf check diagnose
