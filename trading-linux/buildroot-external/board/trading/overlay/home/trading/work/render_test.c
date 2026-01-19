#include <SDL2/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window* window = SDL_CreateWindow("Render Test",
        SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
        1920, 1080, SDL_WINDOW_SHOWN | SDL_WINDOW_FULLSCREEN);

    if (!window) {
        fprintf(stderr, "Window creation failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);

    if (!renderer) {
        fprintf(stderr, "Renderer creation failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    printf("Renderer created successfully!\n");
    printf("Driver: %s\n", SDL_GetCurrentVideoDriver());

    SDL_RendererInfo info;
    SDL_GetRendererInfo(renderer, &info);
    printf("Renderer: %s\n", info.name);
    printf("Flags: %s%s%s\n",
        (info.flags & SDL_RENDERER_ACCELERATED) ? "ACCELERATED " : "",
        (info.flags & SDL_RENDERER_SOFTWARE) ? "SOFTWARE " : "",
        (info.flags & SDL_RENDERER_PRESENTVSYNC) ? "VSYNC" : "");

    // Animation loop
    int running = 1;
    Uint32 start_time = SDL_GetTicks();
    int frame = 0;

    while (running && (SDL_GetTicks() - start_time) < 10000) { // 10 second test
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT ||
                (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE)) {
                running = 0;
            }
        }

        float t = (SDL_GetTicks() - start_time) / 1000.0f;

        // Clear to black
        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        SDL_RenderClear(renderer);

        // Animated red rectangle
        SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);
        SDL_Rect rect1 = {
            (int)(100 + sin(t * 2) * 100),
            100,
            200, 150
        };
        SDL_RenderFillRect(renderer, &rect1);

        // Green rectangle
        SDL_SetRenderDrawColor(renderer, 0, 255, 0, 255);
        SDL_Rect rect2 = {600, 200, 300, 200};
        SDL_RenderFillRect(renderer, &rect2);

        // Blue rectangle (pulsing)
        SDL_SetRenderDrawColor(renderer, 0, 0, 255, 255);
        int size = (int)(150 + sin(t * 3) * 50);
        SDL_Rect rect3 = {1200, 400, size, size};
        SDL_RenderFillRect(renderer, &rect3);

        // White diagonal lines
        SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
        for (int i = 0; i < 10; i++) {
            SDL_RenderDrawLine(renderer, i * 100, 0, i * 100, 1080);
        }

        // Cyan circle (via points)
        SDL_SetRenderDrawColor(renderer, 0, 255, 255, 255);
        int cx = 960, cy = 540;
        int radius = (int)(100 + sin(t * 4) * 30);
        for (int angle = 0; angle < 360; angle += 1) {
            float rad = angle * M_PI / 180.0f;
            int x = cx + (int)(cos(rad) * radius);
            int y = cy + (int)(sin(rad) * radius);
            SDL_RenderDrawPoint(renderer, x, y);
        }

        SDL_RenderPresent(renderer);

        frame++;
        if (frame % 60 == 0) {
            printf("Frame %d (%.1f fps)\n", frame, frame / t);
        }
    }

    printf("Test complete. Rendered %d frames\n", frame);

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
//gcc render_test.c -o render_test $(sdl2-config --cflags --libs) -lm
//SDL_VIDEODRIVER=kmsdrm ./render_test
