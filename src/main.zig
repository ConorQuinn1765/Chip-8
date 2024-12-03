const std = @import("std");
const raylib = @cImport(@cInclude("raylib.h"));
const time = std.time;

const Rng = std.Random.DefaultPrng;

var memory: [4096]u8 = undefined;
var stack: [64]u16 = undefined;
var regs: [16]u8 = undefined;
var pc: u16 = 0x200;
var sp: u16 = 0;
var I: u16 = 0;

var sprite_addr: [16]u16 = undefined;
var screen: [32][64]bool = undefined;
var keymap: std.AutoHashMap(u8, u8) = undefined;
var delay_timer: u8 = 0;
var sound_timer: u8 = 0;

const keyWait = struct {
    waiting: bool,
    pressed: bool,
    key: c_int,
    register: u8,
};

var wait = keyWait{
    .waiting = false,
    .pressed = false,
    .key = 0,
    .register = 0,
};

fn createKeyMap() !std.AutoHashMap(u8, u8) {
    var map = std.AutoHashMap(u8, u8).init(std.heap.page_allocator);

    try map.put(0x1, 49); // 1
    try map.put(0x2, 50); // 2
    try map.put(0x3, 51); // 3
    try map.put(0xc, 52); // 4
    try map.put(0x4, 81); // Q
    try map.put(0x5, 87); // W
    try map.put(0x6, 69); // E
    try map.put(0xD, 82); // R
    try map.put(0x7, 65); // A
    try map.put(0x8, 83); // S
    try map.put(0x9, 68); // D
    try map.put(0xE, 70); // F
    try map.put(0xA, 90); // Z
    try map.put(0x0, 88); // X
    try map.put(0xB, 67); // C
    try map.put(0xF, 86); // V

    return map;
}

fn loadFile(filename: []const u8) !void {
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    const size = try file.readAll(&buf);

    for (0..size) |i| {
        memory[pc + i] = buf[i];
    }
}

fn loadSprites() void {
    const sprites: [16][5]u8 = .{
        .{ 0xF0, 0x90, 0x90, 0x90, 0xF0 }, // 0
        .{ 0x20, 0x60, 0x20, 0x20, 0x70 }, // 1
        .{ 0xF0, 0x10, 0xF0, 0x80, 0xF0 }, // 2
        .{ 0xF0, 0x10, 0xF0, 0x10, 0xF0 }, // 3
        .{ 0x90, 0x90, 0xF0, 0x10, 0x10 }, // 4
        .{ 0xF0, 0x80, 0xF0, 0x10, 0xF0 }, // 5
        .{ 0xF0, 0x80, 0xF0, 0x90, 0xF0 }, // 6
        .{ 0xF0, 0x10, 0x20, 0x40, 0x40 }, // 7
        .{ 0xF0, 0x90, 0xF0, 0x90, 0xF0 }, // 8
        .{ 0xF0, 0x90, 0xF0, 0x10, 0xF0 }, // 9
        .{ 0xF0, 0x90, 0xF0, 0x90, 0x90 }, // A
        .{ 0xE0, 0x90, 0xE0, 0x90, 0xE0 }, // B
        .{ 0xF0, 0x80, 0x80, 0x80, 0xF0 }, // C
        .{ 0xE0, 0x90, 0x90, 0x90, 0xE0 }, // D
        .{ 0xF0, 0x80, 0xF0, 0x80, 0xF0 }, // E
        .{ 0xF0, 0x80, 0xF0, 0x80, 0x80 }, // F
    };

    var idx: u16 = 0x100;
    for (sprites, 0..) |sprite, i| {
        sprite_addr[i] = idx;
        for (sprite) |c| {
            memory[idx] = c;
            idx += 1;
        }
    }
}

fn dumpMemory() void {
    for (0..4096) |i| {
        if (i % 16 == 0) {
            std.debug.print("\n0x{X:0>4}: ", .{i});
        }

        std.debug.print("{X:0>4} ", .{memory[i]});
    }
}

fn BCD(x: u8) void {
    var val = x;
    const tens = val % 10;
    val /= 10;
    const hundreds = val % 10;
    val /= 10;

    memory[I] = val;
    memory[I + 1] = hundreds;
    memory[I + 2] = tens;
}

fn waitKey(reg: u8) void {
    wait.waiting = true;
    wait.pressed = false;
    wait.register = reg;
}

fn reg_dump(x: u8) void {
    for (0..x + 1) |i| {
        memory[I + i] = regs[i];
    }
}

fn reg_load(x: u8) void {
    for (0..x + 1) |i| {
        regs[i] = memory[I + i];
    }
}

fn clearDisplay() void {
    for (0..32) |i| {
        @memset(&screen[i], false);
    }
}

fn draw(x: u8, y: u8, n: u8) void {
    const px = x % 64;
    const py = y % 32;

    regs[0xf] = 0;
    for (0..n) |i| {
        if (py + i >= 32) break;

        const mask: [8]u8 = .{ 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01 };
        const byte = memory[I + i];
        for (0..8) |j| {
            if (px + j >= 64) break;

            if (byte & mask[j] == mask[j]) {
                if (screen[py + i][px + j]) {
                    screen[py + i][px + j] = false;
                    regs[0xf] = 1;
                } else {
                    screen[py + i][px + j] = true;
                }
            }
        }
    }
}

fn parseCmd8(x: u8, y: u8, n: u8) void {
    switch (n) {
        0x0 => {
            regs[x] = regs[y];
        },
        0x1 => {
            regs[x] |= regs[y];
        },
        0x2 => {
            regs[x] &= regs[y];
        },
        0x3 => {
            regs[x] ^= regs[y];
        },
        0x4 => {
            if ((std.math.maxInt(u8) - regs[x]) < regs[y]) {
                regs[x] = regs[y] - (std.math.maxInt(u8) - regs[x]) - 1;
                regs[0xf] = 1;
            } else {
                regs[x] += regs[y];
                regs[0xf] = 0;
            }
        },
        0x5 => {
            if (regs[x] < regs[y]) {
                regs[x] = std.math.maxInt(u8) - (regs[y] - regs[x]) + 1;
                regs[0xf] = 0;
            } else {
                regs[x] -= regs[y];
                regs[0xf] = 1;
            }
        },
        0x6 => {
            const flag: u8 = regs[x] & 0x01;
            regs[x] >>= 1;
            regs[0xf] = flag;
        },
        0x7 => {
            if (regs[y] < regs[x]) {
                regs[x] = std.math.maxInt(u8) - (regs[x] - regs[y]) + 1;
                regs[0xf] = 0;
            } else {
                regs[x] = regs[y] - regs[x];
                regs[0xf] = 1;
            }
        },
        0xe => {
            const flag: u8 = (regs[x] & 0x80) >> 7;
            regs[x] <<= 1;
            regs[0xf] = flag;
        },
        else => {},
    }
}

fn parseCmdF(x: u8, nn: u8) void {
    switch (nn) {
        0x07 => {
            regs[x] = delay_timer;
        },
        0x0a => {
            waitKey(x);
        },
        0x15 => {
            delay_timer = regs[x];
        },
        0x18 => {
            sound_timer = regs[x];
        },
        0x1e => {
            if (std.math.maxInt(u16) - I < regs[x]) {
                I = regs[x] - (std.math.maxInt(u16) - I) - 1;
            } else {
                I += regs[x];
            }
        },
        0x29 => {
            I = sprite_addr[regs[x]];
        },
        0x33 => {
            BCD(regs[x]);
        },
        0x55 => {
            reg_dump(x);
        },
        0x65 => {
            reg_load(x);
        },
        else => {},
    }
}

fn parseOpcode(opcode: u16) void {
    const cmd: u8 = @truncate((opcode & 0xf000) >> 12);
    const x: u8 = @truncate((opcode & 0x0f00) >> 8);
    const y: u8 = @truncate((opcode & 0x00f0) >> 4);
    const n: u8 = @truncate((opcode & 0x000f));
    const nn: u8 = @truncate((opcode & 0x00ff));
    const nnn: u16 = (opcode & 0x0fff);

    switch (cmd) {
        0 => {
            if (nn == 0xe0) {
                // Display Clear
                clearDisplay();
            } else if (nn == 0xee) {
                // Return;
                if (sp > 0) {
                    sp -= 1;
                    pc = stack[sp];
                }
            } else {}
        },
        1 => {
            // goto nnn;
            pc = nnn;
        },
        2 => {
            // jump and link nnn
            stack[sp] = pc;
            sp += 1;
            pc = nnn;
        },
        3 => {
            // if(vx == nn)
            if (regs[x] == nn)
                pc += 2;
        },
        4 => {
            // if(vx != nn)
            if (regs[x] != nn)
                pc += 2;
        },
        5 => {
            // if(vx == vy)
            if (regs[x] == regs[y])
                pc += 2;
        },
        6 => {
            // vx = nn
            regs[x] = nn;
        },
        7 => {
            // vx += nn
            if (std.math.maxInt(u8) - regs[x] < nn) {
                regs[x] = nn - (std.math.maxInt(u8) - regs[x]) - 1;
            } else {
                regs[x] += nn;
            }
        },
        8 => {
            parseCmd8(x, y, n);
        },
        9 => {
            if (n == 0) {
                if (regs[x] != regs[y])
                    pc += 2;
            } else {}
        },
        10 => {
            I = nnn;
        },
        11 => {
            pc = regs[0] + nnn;
        },
        12 => {
            var rand = Rng.init(0);
            regs[x] = rand.random().int(u8) & nn;
        },
        13 => {
            draw(regs[x], regs[y], n);
        },
        14 => {
            if (nn == 0x9e) {
                // if(key() == vx) pc += 2;
                if (keymap.get(regs[x])) |key| {
                    if (raylib.IsKeyDown(@intCast(key))) {
                        pc += 2;
                    }
                }
            } else if (nn == 0xa1) {
                // if(key() != vx) pc += 2;
                if (keymap.get(regs[x])) |key| {
                    if (raylib.IsKeyUp(@intCast(key))) {
                        pc += 2;
                    }
                }
            } else {
                // error
            }
        },
        15 => {
            parseCmdF(x, nn);
        },
        else => {},
    }
}

fn getOpcode() u16 {
    const opcode = (@as(u16, memory[pc]) << 8) | memory[pc + 1];
    pc += 2;
    return opcode;
}

pub fn main() !void {
    @memset(&memory, 0);
    @memset(&stack, 0);
    @memset(&regs, 0);

    for (0..32) |i| {
        @memset(&screen[i], false);
    }

    keymap = try createKeyMap();
    loadSprites();

    var args = std.process.args();
    _ = args.skip();
    if (args.next()) |file| {
        try loadFile(file);
    } else {
        std.debug.print("You must provide a chip-8 rom file\n", .{});
        return;
    }

    raylib.InitWindow(640, 320, "Chip 8 Emulator");
    raylib.SetTargetFPS(500);

    var startTime = try time.Instant.now();
    var done = false;

    while (!raylib.WindowShouldClose()) {
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.BLACK);

        const endTime = try time.Instant.now();
        if ((endTime.since(startTime)) > (1 / 60)) {
            if (delay_timer > 0)
                delay_timer -= 1;
            if (sound_timer > 0)
                sound_timer -= 1;

            startTime = endTime;
        }

        if (wait.waiting) {
            const key = raylib.GetKeyPressed();
            if (key != 0) {
                if (!wait.pressed) {
                    wait.pressed = true;
                    wait.key = key;
                }
            }

            if (wait.waiting and raylib.IsKeyUp(wait.key)) {
                var it = keymap.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* == wait.key) {
                        regs[wait.register] = entry.key_ptr.*;
                        wait = keyWait{
                            .waiting = false,
                            .pressed = false,
                            .key = 0,
                            .register = 0,
                        };

                        break;
                    }
                }
            }
        }

        if (!done and !wait.waiting) {
            const opcode = getOpcode();
            if (opcode == 0x0000) {
                done = true;
            } else {
                parseOpcode(opcode);
            }
        }

        for (0..32) |y| {
            for (0..64) |x| {
                if (screen[y][x]) {
                    raylib.DrawRectangle(@intCast(x * 10), @intCast(y * 10), 10, 10, raylib.RAYWHITE);
                }
            }
        }

        raylib.EndDrawing();
    }

    raylib.CloseWindow();
}
