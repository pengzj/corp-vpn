const std = @import("std");
const rt = @import("../../runtime.zig");

pub const Socks5Auth = union(enum) {
    none: void,
    userpass: struct { username: []const u8, password: []const u8 },
};

pub fn connect(
    allocator: std.mem.Allocator,
    proxy_host: []const u8,
    proxy_port: u16,
    auth: Socks5Auth,
    target_host: []const u8,
    target_port: u16,
) !std.Io.net.Stream {
    const ip = std.Io.net.IpAddress.parse(proxy_host, proxy_port) catch
        try resolveDomain(allocator, proxy_host, proxy_port);
    const stream = try ip.connect(rt.io, .{ .mode = .stream });
    errdefer stream.close(rt.io);

    var rbuf: [1024]u8 = undefined;
    var wbuf: [1024]u8 = undefined;
    var reader = stream.reader(rt.io, &rbuf);
    var writer = stream.writer(rt.io, &wbuf);

    switch (auth) {
        .none => try writer.interface.writeAll(&[_]u8{ 0x05, 1, 0x00 }),
        .userpass => try writer.interface.writeAll(&[_]u8{ 0x05, 2, 0x00, 0x02 }),
    }
    try writer.interface.flush();

    const ver = try reader.interface.takeByte();
    const method = try reader.interface.takeByte();
    if (ver != 0x05) return error.InvalidVersion;
    if (method == 0xFF) return error.NoAcceptableAuth;

    if (method == 0x02) {
        const up = switch (auth) { .userpass => |u| u, else => return error.AuthRequired };
        try writer.interface.writeByte(0x01);
        try writer.interface.writeByte(@intCast(up.username.len));
        try writer.interface.writeAll(up.username);
        try writer.interface.writeByte(@intCast(up.password.len));
        try writer.interface.writeAll(up.password);
        try writer.interface.flush();
        _ = try reader.interface.takeByte();
        if (try reader.interface.takeByte() != 0x00) return error.AuthFailed;
    }

    try writer.interface.writeAll(&[_]u8{ 0x05, 0x01, 0x00, 0x03 });
    try writer.interface.writeByte(@intCast(target_host.len));
    try writer.interface.writeAll(target_host);
    try writer.interface.writeInt(u16, target_port, .big);
    try writer.interface.flush();

    _ = try reader.interface.takeByte();
    if (try reader.interface.takeByte() != 0x00) return error.ConnectRefused;
    _ = try reader.interface.takeByte();
    const atyp = try reader.interface.takeByte();
    switch (atyp) {
        0x01 => { var s: [4]u8 = undefined; try reader.interface.readSliceAll(&s); },
        0x03 => { const l = try reader.interface.takeByte(); var s: [256]u8 = undefined; try reader.interface.readSliceAll(s[0..l]); },
        0x04 => { var s: [16]u8 = undefined; try reader.interface.readSliceAll(&s); },
        else => return error.UnknownAtyp,
    }
    _ = try reader.interface.takeInt(u16, .big);
    return stream;
}

fn resolveDomain(allocator: std.mem.Allocator, host: []const u8, port: u16) !std.Io.net.IpAddress {
    _ = allocator;
    const hostname = try std.Io.net.HostName.init(host);
    var elem_buf: [2]std.Io.net.HostName.LookupResult = undefined;
    var queue: std.Io.Queue(std.Io.net.HostName.LookupResult) = .init(&elem_buf);
    var cname_buf: [std.Io.net.HostName.max_len]u8 = undefined;
    var task = try rt.io.concurrent(std.Io.net.HostName.lookup, .{
        hostname, rt.io, &queue, .{ .port = port, .canonical_name_buffer = &cname_buf },
    });
    defer task.cancel(rt.io) catch {};
    while (queue.getOne(rt.io)) |result| switch (result) {
        .address => |addr| return addr,
        else => {},
    } else |_| {}
    return error.UnknownHost;
}
