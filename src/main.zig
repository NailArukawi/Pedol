const std = @import("std");
const toml = @import("toml.zig");
const Pedal = @import("pedal.zig").Pedal;
const PedalEvent = @import("pedal.zig").PedalEvent;

const linux = std.os.linux;

const c = @cImport({
    @cInclude("hidapi/hidapi.h");
    @cInclude("linux/uinput.h");
});

var keys: [12]c_ushort = undefined;
var l_keys: []c_ushort = undefined;
var m_keys: []c_ushort = undefined;
var r_keys: []c_ushort = undefined;

var vendor_id: c_ushort = undefined;
var product_id: c_ushort = undefined;

pub fn main() !noreturn {
    try init();
    defer deinit();

    // setup Pedal
    var buf: [8]u8 = undefined;
    var pedal = try Pedal.init(vendor_id, product_id, &buf);
    defer pedal.deinit();

    // setup Viritual input
    const flags = std.os.linux.O.WRONLY | std.os.linux.O.NONBLOCK;
    var fd = @as(c_int, @intCast(linux.open("/dev/uinput", flags, 0x644)));

    // register the peys Pedol can press
    const key_count = l_keys.len + m_keys.len + r_keys.len;
    for (keys[0..key_count]) |key| register_keys(fd, key);

    var usetup: c.uinput_setup = undefined;
    create_pedol_device(fd, &usetup);
    defer std.debug.assert(linux.ioctl(fd, c.UI_DEV_DESTROY, 0) == 0);

    //std.time.sleep(10);
    while (true) {
        const event = pedal.poll_event() orelse continue;
        switch (event) {
            .press_left => for (l_keys) |key| press_key(fd, key, 1),
            .release_left => for (l_keys) |key| press_key(fd, key, 0),
            .press_middle => for (m_keys) |key| press_key(fd, key, 1),
            .release_middle => for (m_keys) |key| press_key(fd, key, 0),
            .press_right => for (r_keys) |key| press_key(fd, key, 1),
            .release_right => for (r_keys) |key| press_key(fd, key, 0),
        }
    }
}

fn create_pedol_device(fd: c_int, usetup: *c.uinput_setup) void {
    usetup.* = std.mem.zeroes(c.uinput_setup);
    usetup.id.bustype = c.BUS_USB;
    usetup.id.vendor = 69;
    usetup.id.product = 420;
    usetup.name[0] = 'P';
    usetup.name[1] = 'e';
    usetup.name[2] = 'd';
    usetup.name[3] = 'o';
    usetup.name[4] = 'l';
    usetup.name[5] = 0;

    std.debug.assert(linux.ioctl(fd, c.UI_DEV_SETUP, @intFromPtr(usetup)) == 0);
    std.debug.assert(linux.ioctl(fd, c.UI_DEV_CREATE, 0) == 0);
}

fn press_key(fd: c_int, key: c_ushort, val: c_int) void {
    emit(fd, c.EV_KEY, key, val);
    emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
}

fn register_keys(fd: c_int, key: c_ushort) void {
    std.debug.assert(linux.ioctl(fd, c.UI_SET_EVBIT, c.EV_KEY) == 0);
    std.debug.assert(linux.ioctl(fd, c.UI_SET_KEYBIT, key) == 0);
}

inline fn emit(fd: c_int, event_type: c_ushort, code: c_ushort, val: c_int) void {
    var ie: c.input_event = .{ .type = event_type, .code = code, .value = val, .time = .{
        .tv_sec = 0,
        .tv_usec = 0,
    } };

    var to_write = @as([*]u8, @ptrCast(&ie));
    _ = linux.write(fd, to_write, @sizeOf(c.input_event));
}

fn init() !void {
    _ = c.hid_init();

    var config_parser = try toml.parseFile(std.heap.c_allocator, "./map.toml");
    defer config_parser.deinit();

    var config = try config_parser.parse();
    defer config.deinit();

    const left = config.keys.get("left").?;
    switch (left) {
        .Integer => |key| {
            l_keys = keys[0..1];
            l_keys[0] = @as(c_ushort, @intCast(key));
        },
        .Array => |key_array| {
            const len = key_array.items.len;
            l_keys = keys[0..len];

            for (key_array.items, 0..) |key, i| l_keys[i] = @as(c_ushort, @intCast(key.Integer));
        },
        else => @panic("left type is unsupported"),
    }

    const middle = config.keys.get("middle").?;
    switch (middle) {
        .Integer => |key| {
            const offset = l_keys.len;
            m_keys = keys[offset .. 1 + offset];
            m_keys[0] = @as(c_ushort, @intCast(key));
        },
        .Array => |key_array| {
            const offset = l_keys.len;
            const len = key_array.items.len;
            m_keys = keys[offset .. len + offset];

            for (key_array.items, 0..) |key, i| m_keys[i] = @as(c_ushort, @intCast(key.Integer));
        },
        else => @panic("middle type is unsupported"),
    }

    const right = config.keys.get("right").?;
    switch (right) {
        .Integer => |key| {
            const offset = l_keys.len + m_keys.len;
            r_keys = keys[offset .. 1 + offset];
            r_keys[0] = @as(c_ushort, @intCast(key));
        },
        .Array => |key_array| {
            const offset = l_keys.len + m_keys.len;
            const len = key_array.items.len;
            r_keys = keys[offset .. len + offset];

            for (key_array.items, 0..) |key, i| r_keys[i] = @as(c_ushort, @intCast(key.Integer));
        },
        else => @panic("middle type is unsupported"),
    }

    vendor_id = @as(c_ushort, @intCast(config.keys.get("vendor_id").?.Integer));
    product_id = @as(c_ushort, @intCast(config.keys.get("product_id").?.Integer));
}

fn deinit() void {
    _ = c.hid_exit();
}
