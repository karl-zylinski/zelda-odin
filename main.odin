package main

import SDL "vendor:sdl2"
import IMG "vendor:sdl2/image"
import TTF "vendor:sdl2/ttf"
import "core:fmt"
import "core:math"
import "core:c"
import "core:os"
import "core:mem"
import "core:math/linalg"
import "core:runtime"

scaling :: 4

EditorKey :: enum { None, Flip, Save };
Key :: enum { None, Up, Down, Left, Right, A, B, Select, Start };

Input :: struct {
    mouse_pos: [2]i32,
    mouse_held: bool,
    mouse_clicked: bool,
    right_button_held: bool,

    pressed_keys: [len(Key)]bool,
    released_keys: [len(Key)]bool,
    held_keys: [len(Key)]bool,

    pressed_editor_keys: [len(EditorKey)]bool,
    released_editor_keys: [len(EditorKey)]bool,
    held_editor_keys: [len(EditorKey)]bool,
}

input : Input

sdl_scancode_to_key :: proc(scancode: SDL.Scancode) -> Key {
    using SDL.Scancode

    #partial switch scancode {
        case LEFT: return Key.Left
        case RIGHT: return Key.Right
        case UP: return Key.Up
        case DOWN: return Key.Down
        case Z: return Key.A
        case X: return Key.B
        case RETURN: return Key.Start
        case SPACE: return Key.Select
    }

    return Key.None
}

sdl_scancode_to_editor_key :: proc(scancode: SDL.Scancode) -> EditorKey {
    using SDL.Scancode

    #partial switch scancode {
        case F: return EditorKey.Flip
        case S: return EditorKey.Save
    }

    return EditorKey.None
}

input_update :: proc(keydowns: [dynamic]SDL.Keysym, keyups: [dynamic]SDL.Keysym) {
    input.pressed_keys = {}

    for keydown in keydowns {
        key := sdl_scancode_to_key(keydown.scancode)
        input.pressed_keys[key] = true;
        input.held_keys[key] = true;
        editor_key := sdl_scancode_to_editor_key(keydown.scancode)
        input.pressed_editor_keys[editor_key] = true;
        input.held_editor_keys[editor_key] = true;
    }   

    for keyup in keyups {
        key := sdl_scancode_to_key(keyup.scancode)
        input.released_keys[key] = true;
        input.held_keys[key] = false;
        editor_key := sdl_scancode_to_editor_key(keyup.scancode)
        input.released_editor_keys[editor_key] = true;
        input.held_editor_keys[editor_key] = false;
    }

    mouse_pos := SDL.Point{}
    mouse_button := SDL.GetMouseState(&mouse_pos.x, &mouse_pos.y)

    input.mouse_pos.x = mouse_pos.x / scaling
    input.mouse_pos.y = mouse_pos.y / scaling
    left_mouse_down := mouse_button == SDL.BUTTON_LEFT
    input.mouse_clicked = false

    if (!input.mouse_held && left_mouse_down) {
        input.mouse_clicked = true
    }

    input.right_button_held = false
    if (mouse_button == 4) {
        input.right_button_held = true
    }

    input.mouse_held = left_mouse_down
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
    pos: [2]i32,
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

Tile :: struct {
    idx: i16,
    coord_x: u16,
    coord_y: u16,
    flip: bool,
}

cur_level := [704]Tile { 0..< 704 = { idx = -1 } }

player_update :: proc(player: ^Player) {
    move := [2]i32 {}
    new_anim : ^AnimatedSprite = nil

    if input.held_keys[Key.Left] {
        move.x -= 1;
        new_anim = &player.anim_left
    }

    if input.held_keys[Key.Right] {
        move.x += 1;
        new_anim = &player.anim_right
    }

    if input.held_keys[Key.Up] {
        move.y -= 1;
        new_anim = &player.anim_up
    }

    if input.held_keys[Key.Down] {
        move.y += 1;
        new_anim = &player.anim_down
    }

    if (new_anim != nil) {
        entity_set_animation(player, new_anim)
    }

    player_tile0 := u32(((player.pos.y + move.y - 64 + 16)) / 8) * 32 + u32((player.pos.x + move.x + 1) / 8)
    player_tile1 := u32(((player.pos.y + move.y - 64 + 16)) / 8) * 32 + u32((player.pos.x + move.x + 16 - 1) / 8)

    if player_tile0 < 0 || player_tile1 < 0 || player_tile0 > 704 || player_tile1 > 704 || cur_level[player_tile0].idx != -1 || cur_level[player_tile1].idx != -1  {
        move = {}
    }

    player.pos = player.pos + move;
    animator_update(&player.animator, linalg.length2(move) == 0 ? 0 : time.dt)
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

generate_tilemap :: proc(tex: ^SDL.Texture, tilemap: ^[256]Tile) {
    for i : i16 = 0; i < 256; i += 1 {
        tilemap[i] = {
            idx = i,
            coord_x = u16((i % 16) + (i >= len(tilemap)/2 ? 16 : 0)),
            coord_y = u16((i / 16) - (i >= len(tilemap)/2 ? 8 : 0)),
        }
    }
}

BrushTile :: struct {
}

Brush :: struct {
    tiles: [dynamic]i16,
}

EditorState :: struct {
    brush: Brush,
    brush_start: [2]i32,
    brush_size: [2]i32,
}

vec2_to_sdl_point :: proc(v: [2]i32) -> SDL.Point {
    return SDL.Point { i32(v.x), i32(v.y) }
}

editor_state := EditorState {}

update_editor :: proc(tilemap: ^[256]Tile, tilemap_img: ^SDL.Texture) {
    hover_tile :i16= -1
    mouse_pos := vec2_to_sdl_point(input.mouse_pos)

    for tile_idx := 0; tile_idx < len(tilemap); tile_idx += 1 {
        tile := &tilemap[tile_idx]

        src_rect := SDL.Rect {
            i32((tile.idx % 16) * 8),
            i32((tile.idx / 16) * 8),
            8,
            8,
        }

        dst_rect := SDL.Rect {
            i32(tile.coord_x * 8),
            i32(tile.coord_y * 8),
            8,
            8,
        }

        SDL.RenderCopy(renderer, tilemap_img, &src_rect, &dst_rect)

        if SDL.PointInRect(&mouse_pos, &dst_rect) {
            hover_tile = i16(tile_idx)
        }
    }

    if hover_tile != -1 {
        tile := &tilemap[hover_tile]

        hover_rect := SDL.Rect {
            i32(tile.coord_x * 8),
            i32(tile.coord_y * 8),
            8,
            8,
        }

        SDL.SetRenderDrawColor(renderer, 0x00, 0xFF, 0x00, 0xFF );        
        SDL.RenderDrawRect(renderer, &hover_rect);

        if input.mouse_held {
            if input.mouse_clicked {
                delete(editor_state.brush.tiles)
                editor_state.brush.tiles = {}
            }

            append(&editor_state.brush.tiles, hover_tile)
        }
    }

    if len(editor_state.brush.tiles) > 0 {
        for t in editor_state.brush.tiles {
            tile := &tilemap[t]

            selected_rect := SDL.Rect {
                i32(tile.coord_x * 8),
                i32(tile.coord_y * 8),
                8,
                8,
            }

            SDL.SetRenderDrawColor(renderer, 0xFF, 0x00, 0x00, 0xFF );        
            SDL.RenderDrawRect(renderer, &selected_rect);
        }
    }

    for i :i32= 0; i < 704; i += 1 {
        tile := cur_level[i]

        x :i32= i % 32
        y :i32= i / 32

        dst_rect := SDL.Rect {
            i32(x * 8),
            i32(y * 8) + 16 * 4,
            8,
            8,
        }

        if tile.idx != -1 {
            src_rect := SDL.Rect {
                i32((tile.idx % 16) * 8),
                i32((tile.idx / 16) * 8),
                8,
                8,
            }

            SDL.RenderCopy(renderer, tilemap_img, &src_rect, &dst_rect);
        }

        if SDL.PointInRect(&mouse_pos, &dst_rect) {
            if len(editor_state.brush.tiles) > 0 {
                lowest_x, lowest_y : u16 = 5000, 5000

                for t in editor_state.brush.tiles {
                    tile := &tilemap[t]

                    if tile.coord_x < lowest_x {
                        lowest_x = tile.coord_x
                    }

                    if tile.coord_y < lowest_y {
                        lowest_y = tile.coord_y
                    }
                }

                for t in editor_state.brush.tiles {
                    tile := &tilemap[t]

                    r := dst_rect
                    r.x += i32((tile.coord_x - lowest_x) * 8)
                    r.y += i32((tile.coord_y - lowest_y) * 8)

                    SDL.SetRenderDrawColor(renderer, 0xFF, 0xFF, 0x00, 0xFF);        
                    SDL.RenderDrawRect(renderer, &r);
                }

                if input.mouse_held {
                    size := [2]u16{}
                    for t in editor_state.brush.tiles {
                        tile := &tilemap[t]

                        xdiff := tile.coord_x - lowest_x
                        ydiff := tile.coord_y - lowest_y

                        if xdiff > size.x {
                            size.x = xdiff
                        }

                        if ydiff > size.y {
                            size.y = ydiff
                        }

                        idx := u16(i) + xdiff + ydiff * 32

                        if !input.mouse_clicked && (x - editor_state.brush_start.x) % editor_state.brush_size.x == 0 && (y - editor_state.brush_start.y) % editor_state.brush_size.y == 0 && idx < len(cur_level) {
                            cur_level[idx] = tilemap[t]

                            if input.held_editor_keys[EditorKey.Flip] {
                                cur_level[idx].flip = true
                            }
                        }
                    }

                    if input.mouse_clicked {
                        editor_state.brush_start = {i32(x), i32(y)}
                        editor_state.brush_size = {i32(size.x) + 1, i32(size.y) + 1}
                    }
                }
            }

            if input.right_button_held {
                cur_level[i] = Tile { idx = -1 }
            }
        }
    }
}

test :: proc() {
    defer fmt.println("HEJ")
}

main :: proc() {
    {
        test()
        fmt.println("hoo")
    }
    tracking_allocator: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking_allocator, runtime.default_allocator())
    allocator := mem.tracking_allocator(&tracking_allocator)
    context.allocator = allocator
    SDL.Init(SDL.INIT_EVERYTHING);
    window := SDL.CreateWindow("Karl's Zelda", 200, 200, 256 * scaling, 240 * scaling, SDL.WINDOW_SHOWN);
    renderer = SDL.CreateRenderer(window, -1, SDL.RENDERER_ACCELERATED | SDL.RENDERER_PRESENTVSYNC)
    SDL.RenderSetLogicalSize(renderer, 256, 240)

    IMG.Init(IMG.INIT_PNG);
    TTF.Init();

    {
        f, err := os.open("level")
        defer os.close(f)

        if err == 0 {
            os.read(f, mem.slice_data_cast([]u8, cur_level[:]))
        }
    }
    

    editor_active := true
    editor_state := EditorState {}

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

    tilemap_img := IMG.LoadTexture(renderer, "overworld_green.png")

    tilemap := [256]Tile {}
    generate_tilemap(tilemap_img, &tilemap)

    brush := Brush {}
    selected_tile : i16 = -1

    last_mouse_up := true

    running := true;
    for running {
        keydowns := make([dynamic]SDL.Keysym, context.temp_allocator)
        keyups := make([dynamic]SDL.Keysym, context.temp_allocator)
        e: SDL.Event;
        for SDL.PollEvent(&e) != 0 {
            if e.type == SDL.EventType.QUIT {
                running = false;
            } else if e.type == SDL.EventType.KEYDOWN {
                append(&keydowns, e.key.keysym)
            } else if e.type == SDL.EventType.KEYUP {
                append(&keyups, e.key.keysym)
            }
        }

        input_update(keydowns, keyups)
        time_update()
        player_update(&player)
        SDL.SetRenderDrawColor(renderer, 252, 216, 168, 255)
        SDL.RenderClear(renderer)

        if (editor_active) {
            update_editor(&tilemap, tilemap_img)
        }

        for i := 0; i < 704; i += 1 {
            tile := cur_level[i]

            dst_rect := SDL.Rect {
                i32((i % 32) * 8),
                i32((i / 32) * 8) + 16 * 4,
                8,
                8,
            }

            if tile.idx != -1 {
                src_rect := SDL.Rect {
                    i32((tile.idx % 16) * 8),
                    i32((tile.idx / 16) * 8),
                    8,
                    8,
                }

                SDL.RenderCopyEx(renderer, tilemap_img, &src_rect, &dst_rect, 0, nil, tile.flip ? SDL.RendererFlip.HORIZONTAL : SDL.RendererFlip.NONE);
            }
        }

        entity_render(&player)
        SDL.RenderPresent(renderer)

        if (input.pressed_editor_keys[EditorKey.Save]) {
            f, err := os.open("level", os.O_WRONLY | os.O_CREATE)
            defer os.close(f)

            if err == 0 {
                os.write(f, mem.slice_data_cast([]u8, cur_level[:]))
            }
        }
    }

    delete(editor_state.brush.tiles)
    shutdown_texture_storage()
    SDL.Quit();

    for key, value in tracking_allocator.allocation_map {
        fmt.printf("%v: Leaked %v bytes\n", value.location, value.size)
    }

    mem.tracking_allocator_destroy(&tracking_allocator);
}