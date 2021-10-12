package main

import SDL "vendor:sdl2"
import IMG "vendor:sdl2/image"
import TTF "vendor:sdl2/ttf"
import "core:fmt"
import "core:math"

Key :: enum { Up, Down, Left, Right, A, B, Select, Start };

Input :: struct {
    held: [len(Key)]bool,
}

input : Input

input_update :: proc() {
    keys := SDL.GetKeyboardState(nil)
    input.held = {}

    if keys[SDL.Scancode.LEFT] != 0 {
        input.held[Key.Left] = true;
    }

    if keys[SDL.Scancode.RIGHT] != 0 {
        input.held[Key.Right] = true;
    }

    if keys[SDL.Scancode.UP] != 0 {
        input.held[Key.Up] = true;
        input.held[Key.Right] = false;
        input.held[Key.Left] = false;
    }

    if keys[SDL.Scancode.DOWN] != 0 {
        input.held[Key.Down] = true;
        input.held[Key.Right] = false;
        input.held[Key.Left] = false;
    }

    if keys[SDL.Scancode.Z] != 0 {
        input.held[Key.A] = true;
    }

    if keys[SDL.Scancode.X] != 0 {
        input.held[Key.B] = true;
    }

    if keys[SDL.Scancode.RETURN] != 0 {
        input.held[Key.Start] = true;
    }

    if keys[SDL.Scancode.SPACE] != 0 {
        input.held[Key.Select] = true;
    }

    if (input.held[Key.Left] && input.held[Key.Right]) {
        input.held[Key.Left] = false;
        input.held[Key.Right] = false;
    }

    if (input.held[Key.Up] && input.held[Key.Down]) {
        input.held[Key.Up] = false;
        input.held[Key.Down] = false;
    }
}

Vec2 :: struct {
    x, y: f32,
}

vec2_add :: proc(a: Vec2, b: Vec2) -> Vec2 {
    return Vec2 {
        x = a.x + b.x,
        y = a.y + b.y,
    }
}

vec2_mul :: proc(v: Vec2, s: f32) -> Vec2 {
    return Vec2 {
        x = v.x * s,
        y = v.y * s,
    }
}

vec2_length :: proc(v: Vec2) -> f32 {
    return math.sqrt(v.x * v.x + v.y * v.y)
}

vec2_normalize :: proc(v: Vec2) -> Vec2 {
    l := vec2_length(v)

    if (l == 0) {
        return Vec2 {}
    }

    return vec2_mul(v, 1/l)
}

Rect :: struct {
    x, y, w, h: f32,
}

Time :: struct {
    dt: f32,
    timer: u64,
}

time: Time

time_update :: proc() {
    prev_timer := time.timer
    time.timer = SDL.GetPerformanceCounter()
    time.dt = f32(f64(time.timer - prev_timer) / f64(SDL.GetPerformanceFrequency()));
}

renderer: ^SDL.Renderer
texture_lookup: map[string]^SDL.Texture

init_texture_storage :: proc() {
    texture_lookup = make(map[string]^SDL.Texture)
}

shutdown_texture_storage :: proc() {
    delete(texture_lookup)
}

load_texture :: proc(name: cstring) -> ^SDL.Texture {
    existing := texture_lookup[string(name)]

    if existing != nil {
        return existing
    }

    surface := IMG.Load(name)

    if surface == nil {
        return nil;
    }

    SDL.SetColorKey(surface, SDL.RLEACCEL, SDL.MapRGB(surface.format, 116, 116, 116))
    texture := SDL.CreateTextureFromSurface(renderer, surface)
    texture_lookup[string(name)] = texture
    return texture
}

Sprite :: struct {
    texture: ^SDL.Texture,
    rects: [2]Rect,
}

init_sprite :: proc(texture: ^SDL.Texture, r: Rect, sep: f32) -> Sprite {
    s := Sprite {
        texture = texture,
        rects = {
            r,
            { r.x + r.w + sep, r.y, r.w, r.h },
        },
    }
    return s
}

AnimatedSprite :: struct {
    using sprite: Sprite,
    num_frames: u32,
    frame_time: f32,
    flip: bool,
}

Animator :: struct {
    num_frames: u32,
    frame: u32,
    frame_time: f32,
    timer: f32,
}

animator_update :: proc(a: ^Animator, dt: f32) {
    a.timer += dt

    if (a.timer > a.frame_time) {
        a.timer = 0
        a.frame = a.frame + 1

        if a.frame >= a.num_frames {
            a.frame = 0
        }
    }
}

Entity :: struct {
    pos: Vec2,
    animation: ^AnimatedSprite,
    animator: Animator,
}

Player :: struct {
    using entity: Entity,
    anim_up: AnimatedSprite,
    anim_down: AnimatedSprite,
    anim_left: AnimatedSprite,
    anim_right: AnimatedSprite,
}

level := [176]u32 {
    62,62,62,62,62,62,62,0,0,62,62,62,62,62,62,62,
    62,62,62,62,29,62,63,0,0,62,62,62,62,62,62,62,
    62,62,62,63,0,0,0,0,0,62,62,62,62,62,62,62,
    62,62,63,0,0,0,0,0,0,62,62,62,62,62,62,62,
    62,63,0,0,0,0,0,0,0,61,62,62,62,62,62,62,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    44,45,0,0,0,0,0,0,0,0,0,0,0,0,44,44,
    62,62,0,0,0,0,0,0,0,0,0,0,0,0,62,62,
    62,62,0,0,0,0,0,0,0,0,0,0,0,0,62,62,
    62,62,44,44,44,44,44,44,44,44,44,44,44,44,62,62,
    62,62,62,62,62,62,62,62,62,62,62,62,62,62,62,62,
}

player_update :: proc(player: ^Player) {
    move := Vec2 {}
    new_anim : ^AnimatedSprite = nil

    if input.held[Key.Left] {
        move.x -= 1;
        new_anim = &player.anim_left
    }

    if input.held[Key.Right] {
        move.x += 1;
        new_anim = &player.anim_right
    }

    if input.held[Key.Up] {
        move.y -= 1;
        new_anim = &player.anim_up
    }

    if input.held[Key.Down] {
        move.y += 1;
        new_anim = &player.anim_down
    }

    if (new_anim != nil) {
        entity_set_animation(player, new_anim)
    }

    to_move := vec2_mul(vec2_normalize(move), 70 * time.dt)
    player_tile0 := u32(((player.pos.y + move.y - 64 + 16)) / 16) * 16 + u32((player.pos.x + move.x) / 16)
    player_tile1 := u32(((player.pos.y + move.y - 64 + 16)) / 16) * 16 + u32((player.pos.x + move.x + 16) / 16)

    if player_tile0 < 0 || player_tile1 < 0 || player_tile0 > 176 || player_tile1 > 176 || level[player_tile0] != 0 || level[player_tile1] != 0 {
        to_move = {}
    }

    player.pos = vec2_add(player.pos, to_move);
    animator_update(&player.animator, vec2_length(move) == 0 ? 0 : time.dt)

}

entity_set_animation :: proc(entity: ^Entity, animation: ^AnimatedSprite) {
    if entity.animation == animation {
        return
    }

    entity.animation = animation
    entity.animator = {
        frame_time = animation.frame_time,
        num_frames = animation.num_frames,
    }
}

entity_render :: proc(entity: ^Entity) {
    pos := SDL.Rect{i32(entity.pos.x), i32(entity.pos.y), 16, 16};
    src_rect := SDL.Rect {
        i32(entity.animation.rects[entity.animator.frame].x),
        i32(entity.animation.rects[entity.animator.frame].y),
        i32(entity.animation.rects[entity.animator.frame].w),
        i32(entity.animation.rects[entity.animator.frame].h),
    }
    SDL.RenderCopyEx(renderer, entity.animation.texture, &src_rect, &pos, 0, nil, entity.animation.flip ? SDL.RendererFlip.HORIZONTAL : SDL.RendererFlip.NONE);
}

main :: proc() {
    SDL.Init(SDL.INIT_EVERYTHING);
    window := SDL.CreateWindow("Karl's Zelda", 200, 200, 1024, 960, SDL.WINDOW_SHOWN);
    renderer = SDL.CreateRenderer(window, -1, SDL.RENDERER_ACCELERATED)
    SDL.RenderSetLogicalSize(renderer, 256, 240)

    IMG.Init(IMG.INIT_PNG);
    TTF.Init();

    texture := load_texture("link.png")

    spritedown := init_sprite(texture, Rect{1, 11, 16, 16}, 1)
    spriterightleft := init_sprite(texture, Rect{35, 11, 16, 16}, 1)
    spriteup := init_sprite(texture, Rect{69, 11, 16, 16}, 1)

    player := Player {
        entity = { pos = { 90, 120, } },
        anim_down = {
            sprite = spritedown,
            num_frames = 2,
            frame_time = 0.1,
            flip = false,
        },
        anim_up = {
            sprite = spriteup,
            num_frames = 2,
            frame_time = 0.1,
            flip = false,
        },
        anim_left = {
            sprite = spriterightleft,
            num_frames = 2,
            frame_time = 0.1,
            flip = true,
        },
        anim_right = {
            sprite = spriterightleft,
            num_frames = 2,
            frame_time = 0.1,
            flip = false,
        },
    }

    entity_set_animation(&player, &player.anim_down)

  /*  font := TTF.OpenFont("arial.ttf", 32);
    text_surface := TTF.RenderUTF8_Solid(font, "hej gerry du är söt!", SDL.Color{0, 255, 0, 255});
    text_texture := SDL.CreateTextureFromSurface(renderer, text_surface);
    SDL.FreeSurface(text_surface);*/

    tilemap := IMG.LoadTexture(renderer, "tilemap.png")

    running := true;
    for running {
        e: SDL.Event;
        for SDL.PollEvent(&e) != 0 {
            if e.type == SDL.EventType.QUIT {
                running = false;
            }
        }

        input_update()
        time_update()
        player_update(&player)
        SDL.SetRenderDrawColor(renderer, 255, 192, 122, 255)
        SDL.RenderClear(renderer)

        for i := 0; i < 64; i += 1 {
            tile := 23

            if tile == 0 {
                continue
            }

            src_x := (tile-1) % 18
            src_y := (tile-1) / 18

            src_rect := SDL.Rect {
                i32(src_x * 16 + 1 + src_x),
                i32(src_y * 16 + 1 + src_y),
                16,
                16,
            }

            dst_rect := SDL.Rect {
                i32((i % 16) * 16),
                i32((i / 16) * 16),
                16,
                16,
            }

            SDL.RenderCopy(renderer, tilemap, &src_rect, &dst_rect);
        }

        for i := 0; i < 176; i += 1 {
            tile := level[i]

            if tile == 0 {
                continue
            }

            src_x := (tile-1) % 18
            src_y := (tile-1) / 18

            src_rect := SDL.Rect {
                i32(src_x * 16 + 1 + src_x),
                i32(src_y * 16 + 1 + src_y),
                16,
                16,
            }

            dst_rect := SDL.Rect {
                i32((i % 16) * 16),
                i32((i / 16) * 16) + 16 * 4,
                16,
                16,
            }

            SDL.RenderCopy(renderer, tilemap, &src_rect, &dst_rect);
        }

        entity_render(&player)
        SDL.RenderPresent(renderer)
    }

    SDL.Quit();
}