#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <SDL2/SDL_image.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main() {
    // Initialize SDL
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    // Initialize SDL_ttf
    if (TTF_Init() < 0) {
        fprintf(stderr, "TTF_Init failed: %s\n", TTF_GetError());
        SDL_Quit();
        return 1;
    }

    // Initialize SDL_image
    if (!(IMG_Init(IMG_INIT_PNG) & IMG_INIT_PNG)) {
        fprintf(stderr, "IMG_Init failed: %s\n", IMG_GetError());
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    // Create window
    SDL_Window* window = SDL_CreateWindow("TTF + Image Test",
        SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
        1920, 1080, SDL_WINDOW_SHOWN | SDL_WINDOW_FULLSCREEN);

    if (!window) {
        fprintf(stderr, "Window creation failed: %s\n", SDL_GetError());
        IMG_Quit();
        TTF_Quit();
        SDL_Quit();
        return 1;
    }

    // Create renderer with VSync (like render_test.c)
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);

    if (!renderer) {
        fprintf(stderr, "Renderer creation failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        IMG_Quit();
        TTF_Quit();
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

    // Load fonts
    TTF_Font* font_small = TTF_OpenFont("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 16);
    TTF_Font* font_medium = TTF_OpenFont("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 24);
    TTF_Font* font_large = TTF_OpenFont("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 36);

    if (!font_small || !font_medium || !font_large) {
        fprintf(stderr, "Font loading failed: %s\n", TTF_GetError());
        fprintf(stderr, "Continuing without fonts...\n");
    }

    // Try to load an image (optional - won't fail if not found)
    SDL_Texture* logo = NULL;
    const char* logo_paths[] = {
        "/opt/trading/assets/logo.png",
        "/home/trading/logo.png",
        NULL
    };
    
    for (int i = 0; logo_paths[i] != NULL && !logo; i++) {
        SDL_Surface* surface = IMG_Load(logo_paths[i]);
        if (surface) {
            logo = SDL_CreateTextureFromSurface(renderer, surface);
            SDL_FreeSurface(surface);
            printf("Loaded logo from: %s\n", logo_paths[i]);
        }
    }

    // Pre-render some static text to textures (simulating cached text)
    SDL_Texture* text_title = NULL;
    SDL_Texture* text_subtitle = NULL;
    SDL_Texture* text_label[10] = {NULL};
    SDL_Rect text_title_rect = {0, 0, 0, 0};
    SDL_Rect text_subtitle_rect = {0, 0, 0, 0};
    SDL_Rect text_label_rect[10];

    SDL_Color white = {255, 255, 255, 255};
    SDL_Color cyan = {0, 255, 255, 255};
    SDL_Color gray = {180, 180, 180, 255};

    if (font_large) {
        SDL_Surface* surf = TTF_RenderText_Blended(font_large, "TradingOS Control Panel", cyan);
        if (surf) {
            text_title = SDL_CreateTextureFromSurface(renderer, surf);
            text_title_rect.w = surf->w;
            text_title_rect.h = surf->h;
            text_title_rect.x = (1920 - surf->w) / 2;
            text_title_rect.y = 20;
            SDL_FreeSurface(surf);
        }
    }

    if (font_medium) {
        SDL_Surface* surf = TTF_RenderText_Blended(font_medium, "ARTIX-7 | SUB-5us | GPU Accelerated", gray);
        if (surf) {
            text_subtitle = SDL_CreateTextureFromSurface(renderer, surf);
            text_subtitle_rect.w = surf->w;
            text_subtitle_rect.h = surf->h;
            text_subtitle_rect.x = (1920 - surf->w) / 2;
            text_subtitle_rect.y = 70;
            SDL_FreeSurface(surf);
        }
    }

    // Pre-render some labels (like status boxes and buttons)
    const char* labels[] = {
        "P24: Order Gateway",
        "P25: Market Maker",
        "P26: Execution",
        "CPU: 45.2%",
        "GPU: 78.5%",
        "Memory: 62.1%",
        "START ALL",
        "STOP ALL",
        "RESTART",
        "EXIT"
    };

    if (font_medium) {
        for (int i = 0; i < 10; i++) {
            SDL_Surface* surf = TTF_RenderText_Blended(font_medium, labels[i], white);
            if (surf) {
                text_label[i] = SDL_CreateTextureFromSurface(renderer, surf);
                text_label_rect[i].w = surf->w;
                text_label_rect[i].h = surf->h;
                SDL_FreeSurface(surf);
            }
        }
    }

    // Pre-render dynamic text (will be updated periodically)
    SDL_Texture* text_fps = NULL;
    SDL_Rect text_fps_rect = {10, 10, 0, 0};
    char fps_text[64];
    int fps_update_counter = 0;

    // Animation loop
    int running = 1;
    Uint32 start_time = SDL_GetTicks();
    int frame = 0;

    printf("\n========================================\n");
    printf("Test running for 20 seconds...\n");
    printf("Watch mouse cursor for smoothness!\n");
    printf("========================================\n\n");

    while (running && (SDL_GetTicks() - start_time) < 20000) { // 20 second test
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT ||
                (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE)) {
                running = 0;
            }
        }

        float t = (SDL_GetTicks() - start_time) / 1000.0f;

        // Clear to dark background
        SDL_SetRenderDrawColor(renderer, 20, 20, 30, 255);
        SDL_RenderClear(renderer);

        // Draw logo if available (top-right corner)
        if (logo) {
            SDL_Rect logo_rect = {1920 - 150, 20, 120, 120};
            SDL_RenderCopy(renderer, logo, NULL, &logo_rect);
        }

        // Draw animated background shapes (like render_test.c)
        SDL_SetRenderDrawColor(renderer, 40, 40, 50, 255);
        SDL_Rect bg_rect1 = {
            (int)(50 + sin(t * 0.5) * 30),
            150,
            300, 200
        };
        SDL_RenderFillRect(renderer, &bg_rect1);

        SDL_Rect bg_rect2 = {650, 150, 300, 200};
        SDL_RenderFillRect(renderer, &bg_rect2);

        SDL_Rect bg_rect3 = {1250, 150, 300, 200};
        SDL_RenderFillRect(renderer, &bg_rect3);

        // Draw status box borders (cyan)
        SDL_SetRenderDrawColor(renderer, 0, 255, 255, 255);
        SDL_RenderDrawRect(renderer, &bg_rect1);
        SDL_RenderDrawRect(renderer, &bg_rect2);
        SDL_RenderDrawRect(renderer, &bg_rect3);

        // Draw progress bars (simulating CPU/GPU/Memory)
        int bar_y = 400;
        for (int i = 0; i < 3; i++) {
            // Background
            SDL_SetRenderDrawColor(renderer, 40, 40, 50, 255);
            SDL_Rect bar_bg = {50, bar_y + i * 50, 500, 30};
            SDL_RenderFillRect(renderer, &bar_bg);

            // Foreground (animated)
            float percent = 0.5f + 0.3f * sin(t + i);
            SDL_SetRenderDrawColor(renderer, 0, 200, 100, 255);
            SDL_Rect bar_fg = {50, bar_y + i * 50, (int)(500 * percent), 30};
            SDL_RenderFillRect(renderer, &bar_fg);

            // Border
            SDL_SetRenderDrawColor(renderer, 0, 255, 255, 255);
            SDL_RenderDrawRect(renderer, &bar_bg);
        }

        // Draw buttons
        int btn_y = 1000;
        int btn_x = 50;
        for (int i = 0; i < 4; i++) {
            SDL_SetRenderDrawColor(renderer, 60, 60, 80, 255);
            SDL_Rect btn = {btn_x + i * 180, btn_y, 160, 45};
            SDL_RenderFillRect(renderer, &btn);

            SDL_SetRenderDrawColor(renderer, 0, 255, 255, 255);
            SDL_RenderDrawRect(renderer, &btn);
        }

        // Draw pulsing rectangle (visual feedback of smooth animation)
        SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255);
        int pulse_size = (int)(100 + sin(t * 4) * 30);
        SDL_Rect pulse = {1700, 500, pulse_size, pulse_size};
        SDL_RenderFillRect(renderer, &pulse);

        // Render static text (cached)
        if (text_title) {
            SDL_RenderCopy(renderer, text_title, NULL, &text_title_rect);
        }
        if (text_subtitle) {
            SDL_RenderCopy(renderer, text_subtitle, NULL, &text_subtitle_rect);
        }

        // Render labels
        text_label_rect[0].x = 60;
        text_label_rect[0].y = 160;
        text_label_rect[1].x = 660;
        text_label_rect[1].y = 160;
        text_label_rect[2].x = 1260;
        text_label_rect[2].y = 160;

        text_label_rect[3].x = 60;
        text_label_rect[3].y = 405;
        text_label_rect[4].x = 60;
        text_label_rect[4].y = 455;
        text_label_rect[5].x = 60;
        text_label_rect[5].y = 505;

        text_label_rect[6].x = 70;
        text_label_rect[6].y = 1010;
        text_label_rect[7].x = 250;
        text_label_rect[7].y = 1010;
        text_label_rect[8].x = 430;
        text_label_rect[8].y = 1010;
        text_label_rect[9].x = 630;
        text_label_rect[9].y = 1010;

        for (int i = 0; i < 10; i++) {
            if (text_label[i]) {
                SDL_RenderCopy(renderer, text_label[i], NULL, &text_label_rect[i]);
            }
        }

        // Update FPS text every 10 frames (simulating dynamic text updates)
        fps_update_counter++;
        if (fps_update_counter >= 10 && font_small) {
            if (text_fps) {
                SDL_DestroyTexture(text_fps);
            }
            snprintf(fps_text, sizeof(fps_text), "Frame %d (%.1f fps)", frame, frame / (t + 0.001f));
            SDL_Surface* surf = TTF_RenderText_Blended(font_small, fps_text, white);
            if (surf) {
                text_fps = SDL_CreateTextureFromSurface(renderer, surf);
                text_fps_rect.w = surf->w;
                text_fps_rect.h = surf->h;
                SDL_FreeSurface(surf);
            }
            fps_update_counter = 0;
        }

        if (text_fps) {
            SDL_RenderCopy(renderer, text_fps, NULL, &text_fps_rect);
        }

        SDL_RenderPresent(renderer);

        frame++;
        if (frame % 60 == 0) {
            printf("Frame %d (%.1f fps) - Mouse should be smooth!\n", frame, frame / t);
        }
    }

    printf("\n========================================\n");
    printf("Test complete. Rendered %d frames\n", frame);
    printf("Average FPS: %.1f\n", frame / ((SDL_GetTicks() - start_time) / 1000.0f));
    printf("========================================\n");

    // Cleanup
    if (text_fps) SDL_DestroyTexture(text_fps);
    if (text_title) SDL_DestroyTexture(text_title);
    if (text_subtitle) SDL_DestroyTexture(text_subtitle);
    for (int i = 0; i < 10; i++) {
        if (text_label[i]) SDL_DestroyTexture(text_label[i]);
    }
    if (logo) SDL_DestroyTexture(logo);
    if (font_small) TTF_CloseFont(font_small);
    if (font_medium) TTF_CloseFont(font_medium);
    if (font_large) TTF_CloseFont(font_large);

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    IMG_Quit();
    TTF_Quit();
    SDL_Quit();
    return 0;
}
