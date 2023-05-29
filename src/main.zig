const std = @import("std");
const toml = @import("toml.zig");
const Pedal = @import("pedal.zig").Pedal;
const PedalEvent = @import("pedal.zig").PedalEvent;

const c = @cImport({
    @cInclude("hidapi/hidapi.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("unistd.h");
    @cInclude("linux/input.h");
    @cInclude("linux/uinput.h");
});

var config: *toml.Table = undefined;

var l_key: c_ushort = undefined;
var m_key: c_ushort = undefined;
var r_key: c_ushort = undefined;

pub fn main() !void {
    try init();
    defer deinit();

    // setup Pedal
    var buf: [8]u8 = undefined;
    const vendor_id = @intCast(c_ushort, config.keys.get("vendor_id").?.Integer);
    const product_id = @intCast(c_ushort, config.keys.get("product_id").?.Integer);
    var pedal = try Pedal.init(vendor_id, product_id, &buf);
    defer pedal.deinit();

    // setup Viritual input
    var usetup: c.uinput_setup = undefined;

    const flags = std.os.linux.O.WRONLY | std.os.linux.O.NONBLOCK;
    var fd = try std.os.open("/dev/uinput", flags, 0x777);

    var res = c.ioctl(fd, c.UI_SET_EVBIT, c.EV_KEY);
    if (res < 0) die(res, "ioctl: UI_SET_EVBIT");
    res = c.ioctl(fd, c.UI_SET_KEYBIT, l_key);
    if (res < 0) die(res, "ioctl: UI_SET_KEYBIT");
    std.time.sleep(10);

    res = c.ioctl(fd, c.UI_SET_EVBIT, c.EV_KEY);
    if (res < 0) die(res, "ioctl: UI_SET_EVBIT");
    res = c.ioctl(fd, c.UI_SET_KEYBIT, m_key);
    if (res < 0) die(res, "ioctl: UI_SET_KEYBIT");
    std.time.sleep(10);

    res = c.ioctl(fd, c.UI_SET_EVBIT, c.EV_KEY);
    if (res < 0) die(res, "ioctl: UI_SET_EVBIT");
    res = c.ioctl(fd, c.UI_SET_KEYBIT, r_key);
    if (res < 0) die(res, "ioctl: UI_SET_KEYBIT");
    std.time.sleep(10);

    _ = c.memset(&usetup, 0, @sizeOf(c.uinput_setup));
    usetup.id.bustype = c.BUS_USB;
    usetup.id.vendor = 69;
    usetup.id.product = 420;
    _ = c.strcpy(&usetup.name, "Pedol");

    res = c.ioctl(fd, c.UI_DEV_SETUP, &usetup);
    if (res < 0) die(res, "ioctl: UI_DEV_SETUP");
    res = c.ioctl(fd, c.UI_DEV_CREATE);
    if (res < 0) die(res, "ioctl: UI_DEV_CREATE");
    defer c.ioctl(fd, c.UI_DEV_DESTROY);

    std.time.sleep(100);
    while (true) {
        std.time.sleep(10);
        const event = pedal.poll_event();
        if (event == null) continue;
        switch (event.?) {
            .press_left => {
                emit(fd, c.EV_KEY, l_key, 1);
                emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
            },
            .release_left => {
                emit(fd, c.EV_KEY, l_key, 0);
                emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
            },
            .press_middle => {
                emit(fd, c.EV_KEY, m_key, 1);
                emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
            },
            .release_middle => {
                emit(fd, c.EV_KEY, m_key, 0);
                emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
            },
            .press_right => {
                emit(fd, c.EV_KEY, r_key, 1);
                emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
            },
            .release_right => {
                emit(fd, c.EV_KEY, r_key, 0);
                emit(fd, c.EV_SYN, c.SYN_REPORT, 0);
            },
        }
    }
}

fn emit(fd: c_int, event_type: c_ushort, code: c_ushort, val: c_int) void {
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

    config = try config_parser.parse();
    l_key = @intCast(c_ushort, config.keys.get("left").?.Integer);
    m_key = @intCast(c_ushort, config.keys.get("middle").?.Integer);
    r_key = @intCast(c_ushort, config.keys.get("right").?.Integer);
}

fn deinit() void {
    _ = c.hid_exit();
    config.deinit();
}
