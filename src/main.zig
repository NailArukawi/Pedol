const std = @import("std");
const toml = @import("toml.zig");
const Pedal = @import("pedal.zig").Pedal;
const PedalEvent = @import("pedal.zig").PedalEvent;

const c = @cImport({
    @cInclude("hidapi/hidapi.h");
    @cInclude("string.h");
    @cInclude("unistd.h");
    @cInclude("linux/uinput.h");
});

var config: *toml.Table = undefined;

var keys: [12]c_ushort = undefined;
var l_key: []c_ushort = undefined;
var m_key: []c_ushort = undefined;
var r_key: []c_ushort = undefined;

var vendor_id: c_ushort = undefined;
var product_id: c_ushort = undefined;

pub fn main() !void {
    try init();
    defer deinit();

    // setup Pedal
    var buf: [8]u8 = undefined;
    var pedal = try Pedal.init(vendor_id, product_id, &buf);
    defer pedal.deinit();

    // setup Viritual input
    var usetup: c.uinput_setup = undefined;

    const flags = std.os.linux.O.WRONLY | std.os.linux.O.NONBLOCK;
    var fd = try std.os.open("/dev/uinput", flags, 0x777);

    // register the peys Pedol can press
    const key_count = l_key.len + m_key.len + r_key.len;
    for (keys[0 .. key_count + 1]) |key| {
        register_key(fd, key);
    }

    _ = c.memset(&usetup, 0, @sizeOf(c.uinput_setup));
    usetup.id.bustype = c.BUS_USB;
    usetup.id.vendor = 69;
    usetup.id.product = 420;
    _ = c.strcpy(&usetup.name, "Pedol");

    // create the Pedol device
    var res = c.ioctl(fd, c.UI_DEV_SETUP, &usetup);
    if (res < 0) die(res, "ioctl: UI_DEV_SETUP");
    res = c.ioctl(fd, c.UI_DEV_CREATE);
    if (res < 0) die(res, "ioctl: UI_DEV_CREATE");
    defer c.ioctl(fd, c.UI_DEV_DESTROY);

    std.time.sleep(10);
    while (true) {
        std.time.sleep(5);
        const event = pedal.poll_event();
        if (event == null) continue;
        switch (event.?) {
            .press_left => {
                for (l_key) |key| {
                    emit(fd, c.EV_KEY, key, 1);
                    emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
                }
            },
            .release_left => {
                for (l_key) |key| {
                    emit(fd, c.EV_KEY, key, 0);
                    emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
                }
            },
            .press_middle => {
                for (m_key) |key| {
                    emit(fd, c.EV_KEY, key, 1);
                    emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
                }
            },
            .release_middle => {
                for (m_key) |key| {
                    emit(fd, c.EV_KEY, key, 0);
                    emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
                }
            },
            .press_right => {
                for (r_key) |key| {
                    emit(fd, c.EV_KEY, key, 1);
                    emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
                }
            },
            .release_right => {
                for (r_key) |key| {
                    emit(fd, c.EV_KEY, key, 0);
                    emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
                }
            },
        }
    }
}

fn register_key(fd: c_int, key: c_ushort) void {
    var res = c.ioctl(fd, c.UI_SET_EVBIT, c.EV_KEY);
    if (res < 0) die(res, "ioctl: UI_SET_EVBIT");
    res = c.ioctl(fd, c.UI_SET_KEYBIT, key);
    if (res < 0) die(res, "ioctl: UI_SET_KEYBIT");
    std.time.sleep(5);
}

inline fn emit(fd: c_int, event_type: c_ushort, code: c_ushort, val: c_int) void {
    var ie: c.input_event = undefined;

    ie.type = event_type;
    ie.code = code;
    ie.value = val;
    // timestamp values below are ignored
    ie.time.tv_sec = 0;
    ie.time.tv_usec = 0;

    _ = c.write(fd, &ie, @sizeOf(c.input_event));
}

fn die(id: c_int, msg: []const u8) void {
    std.debug.print("[{}]{s}\n", .{ id, msg });
    @panic("");
}

fn init() !void {
    _ = c.hid_init();

    var config_parser = try toml.parseFile(std.heap.c_allocator, "./map.toml");
    defer config_parser.deinit();

    config = try config_parser.parse();
    const left = config.keys.get("left").?;
    const middle = config.keys.get("middle").?;
    const right = config.keys.get("right").?;
    switch (left) {
        .Integer => |key| {
            l_key = keys[0..1];
            l_key[0] = @intCast(c_ushort, key);
        },
        .Array => |key_array| {
            const len = key_array.items.len;
            l_key = keys[0..len];

            for (key_array.items, 0..) |key, i| {
                l_key[i] = @intCast(c_ushort, key.Integer);
            }
        },
        else => @panic("left has an unsuporet type in map.toml"),
    }

    switch (middle) {
        .Integer => |key| {
            const offset = l_key.len;
            m_key = keys[offset .. 1 + offset];
            m_key[0] = @intCast(c_ushort, key);
        },
        .Array => |key_array| {
            const offset = l_key.len;
            const len = key_array.items.len;
            m_key = keys[offset .. len + offset];

            for (key_array.items, 0..) |key, i| {
                m_key[i] = @intCast(c_ushort, key.Integer);
            }
        },
        else => @panic("middle has an unsuporet type in map.toml"),
    }

    switch (right) {
        .Integer => |key| {
            const offset = l_key.len + m_key.len;
            r_key = keys[offset .. 1 + offset];
            r_key[0] = @intCast(c_ushort, key);
        },
        .Array => |key_array| {
            const offset = l_key.len + m_key.len;
            const len = key_array.items.len;
            r_key = keys[offset .. len + offset];

            for (key_array.items, 0..) |key, i| {
                r_key[i] = @intCast(c_ushort, key.Integer);
            }
        },
        else => @panic("middle has an unsuporet type in map.toml"),
    }

    vendor_id = @intCast(c_ushort, config.keys.get("vendor_id").?.Integer);
    product_id = @intCast(c_ushort, config.keys.get("product_id").?.Integer);
}

fn deinit() void {
    _ = c.hid_exit();
}
