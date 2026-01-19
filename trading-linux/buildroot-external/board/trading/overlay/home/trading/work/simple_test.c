#include <SDL2/SDL.h>
#include <stdio.h>

int main() {
	SDL_Init(SDL_INIT_VIDEO);
	SDL_Window* win = SDL_CreateWindow("Test", 0, 0, 800, 600, SDL_WINDOW_SHOWN);
	SDL_Renderer* ren = SDL_CreateRenderer(win, -1, 0);

	for (int i = 0; i < 300; i++) {
		SDL_SetRenderDrawColor(ren, i % 256, (i * 2) % 256, (i * 3) % 256, 255);
		SDL_RenderClear(ren);
		SDL_RenderPresent(ren);
		SDL_Delay(16);
	}

	SDL_DestroyRenderer(ren);
	SDL_DestroyWindow(win);
	SDL_Quit();
	return 0;
}
//gcc simple_test.c -o simple_test $(sdl2-config --cflags --libs)
//SDL_VIDEODRIVER=kmsdrm ./simple_test
