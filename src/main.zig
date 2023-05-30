const std = @import("std");
const toml = @import("toml.zig");
const Pedal = @import("pedal.zig").Pedal;
const PedalEvent = @import("pedal.zig").PedalEvent;

const c = @cImport({
    @cInclude("hidapi/hidapi.h");
    @cInclude("unistd.h");
    @cInclude("linux/uinput.h");
});

var keys: [12]c_ushort = undefined;
var l_keys: []c_ushort = undefined;
var m_keys: []c_ushort = undefined;
var r_keys: []c_ushort = undefined;

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
    const flags = std.os.linux.O.WRONLY | std.os.linux.O.NONBLOCK;
    var fd = try std.os.open("/dev/uinput", flags, 0x777);

    // register the peys Pedol can press
    const key_count = l_keys.len + m_keys.len + r_keys.len;
    for (keys[0..key_count]) |key| {
        register_keys(fd, key);
    }

    _ = create_pedol_device(fd);
    defer c.ioctl(fd, c.UI_DEV_DESTROY);

    std.time.sleep(10);
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

inline fn create_pedol_device(fd: c_int) c.uinput_setup {
    var usetup: c.uinput_setup = std.mem.zeroes(c.uinput_setup);
    usetup.id.bustype = c.BUS_USB;
    usetup.id.vendor = 69;
    usetup.id.product = 420;
    usetup.name[0] = 'P';
    usetup.name[1] = 'e';
    usetup.name[2] = 'd';
    usetup.name[3] = 'o';
    usetup.name[4] = 'l';
    usetup.name[5] = 0;

    assert_die(c.ioctl(fd, c.UI_DEV_SETUP, &usetup), "ioctl: UI_DEV_SETUP");
    assert_die(c.ioctl(fd, c.UI_DEV_CREATE), "ioctl: UI_DEV_CREATE");
    return usetup;
}

inline fn press_key(fd: c_int, key: c_ushort, val: c_int) void {
    emit(fd, c.EV_KEY, key, val);
    emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
}

fn register_keys(fd: c_int, key: c_ushort) void {
    assert_die(c.ioctl(fd, c.UI_SET_EVBIT, c.EV_KEY), "ioctl: UI_SET_EVBIT");
    assert_die(c.ioctl(fd, c.UI_SET_KEYBIT, key), "ioctl: UI_SET_KEYBIT");
    std.time.sleep(5);
}

inline fn emit(fd: c_int, event_type: c_ushort, code: c_ushort, val: c_int) void {
    var ie: c.input_event = .{ .type = event_type, .code = code, .value = val, .time = .{
        .tv_sec = 0,
        .tv_usec = 0,
    } };

    _ = c.write(fd, &ie, @sizeOf(c.input_event));
}

inline fn assert_die(id: c_int, msg: []const u8) void {
    if (id > -1) return;
    std.debug.print("[{}]{s}\n", .{ id, msg });
    @panic("");
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
            l_keys[0] = @intCast(c_ushort, key);
        },
        .Array => |key_array| {
            const len = key_array.items.len;
            l_keys = keys[0..len];

            for (key_array.items, 0..) |key, i| l_keys[i] = @intCast(c_ushort, key.Integer);
        },
        else => @panic("left has an unsupported type in map.toml"),
    }

    const middle = config.keys.get("middle").?;
    switch (middle) {
        .Integer => |key| {
            const offset = l_keys.len;
            m_keys = keys[offset .. 1 + offset];
            m_keys[0] = @intCast(c_ushort, key);
        },
        .Array => |key_array| {
            const offset = l_keys.len;
            const len = key_array.items.len;
            m_keys = keys[offset .. len + offset];

            for (key_array.items, 0..) |key, i| m_keys[i] = @intCast(c_ushort, key.Integer);
        },
        else => @panic("middle has an unsupported type in map.toml"),
    }

    const right = config.keys.get("right").?;
    switch (right) {
        .Integer => |key| {
            const offset = l_keys.len + m_keys.len;
            r_keys = keys[offset .. 1 + offset];
            r_keys[0] = @intCast(c_ushort, key);
        },
        .Array => |key_array| {
            const offset = l_keys.len + m_keys.len;
            const len = key_array.items.len;
            r_keys = keys[offset .. len + offset];

            for (key_array.items, 0..) |key, i| r_keys[i] = @intCast(c_ushort, key.Integer);
        },
        else => @panic("middle has an unsupported type in map.toml"),
    }

    vendor_id = @intCast(c_ushort, config.keys.get("vendor_id").?.Integer);
    product_id = @intCast(c_ushort, config.keys.get("product_id").?.Integer);
}

fn deinit() void {
    _ = c.hid_exit();
}
