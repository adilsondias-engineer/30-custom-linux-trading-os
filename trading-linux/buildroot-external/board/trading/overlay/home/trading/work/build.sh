 gcc $1.c -o $1 $(sdl2-config --cflags --libs) -lm -I/usr/include/ -D_REENTRANT -L/usr/lib -I/usr/local/include
