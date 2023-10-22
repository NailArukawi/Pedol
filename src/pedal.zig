const std = @import("std");

const c = @cImport(
    @cInclude("hidapi/hidapi.h"),
);

pub const Pedal = struct {
    hid: HIDHandle,
    buf: []u8,
    state: [3]bool = .{ false, false, false },

    pub fn init(vendor_id: c_ushort, product_id: c_ushort, buf: []u8) !@This() {
        var handle = try HIDHandle.open(vendor_id, product_id, null);
        return @This(){
            .hid = handle,
            .buf = buf,
        };
    }

    pub fn deinit(self: @This()) void {
        defer self.hid.close();
    }

    pub fn poll_event(self: *@This()) ?PedalEvent {
        const read = self.hid.read(self.buf);
        // handle change in left pedal
        if ((read[4] == 1) != self.state[0]) {
            if (self.state[0]) {
                self.state[0] = false;
                return PedalEvent.release_left;
            } else {
                self.state[0] = true;
                return PedalEvent.press_left;
            }
        }

        // handle change in middle pedal
        if ((read[5] == 1) != self.state[1]) {
            if (self.state[1]) {
                self.state[1] = false;
                return PedalEvent.release_middle;
            } else {
                self.state[1] = true;
                return PedalEvent.press_middle;
            }
        }

        // handle change in right pedal
        if ((read[6] == 1) != self.state[2]) {
            if (self.state[2]) {
                self.state[2] = false;
                return PedalEvent.release_right;
            } else {
                self.state[2] = true;
                return PedalEvent.press_right;
            }
        }

        return null;
    }
};

pub const PedalEvent = enum {
    press_left,
    release_left,

    press_middle,
    release_middle,

    press_right,
    release_right,
};

const HIDError = error{
    device_not_found,
};

const HIDHandle = struct {
    inner: *c.hid_device,

    pub fn open(vendor_id: c_ushort, product_id: c_ushort, serial_number: [*c]const c_int) !@This() {
        var handle = c.hid_open(vendor_id, product_id, serial_number) orelse return HIDError.device_not_found;

        return @This(){
            .inner = handle,
        };
    }

    pub fn close(self: @This()) void {
        c.hid_close(self.inner);
    }

    pub fn write(self: @This(), data: []u8) c_int {
        return c.hid_write(self.inner, data.ptr, data.len);
    }

    pub fn read(self: @This(), buffer: []u8) []u8 {
        const res = c.hid_read(self.inner, buffer.ptr, buffer.len);

        return buffer[0..@as(usize, @intCast(res))];
    }
};
