const std = @import("std");
const rt = @import("../../runtime.zig");

pub const HttpAuth = union(enum) {
    none: void,
    userpass: struct { username: []const u8, password: []const u8 },
};

pub fn connect(
    allocator: std.mem.Allocator,
    proxy_host: []const u8,
    proxy_port: u16,
    auth: HttpAuth,
    target_host: []const u8,
    target_port: u16,
) !std.Io.net.Stream {
    const ip = std.Io.net.IpAddress.parse(proxy_host, proxy_port) catch
        try resolveDomain(allocator, proxy_host, proxy_port);
    const stream = try ip.connect(rt.io, .{ .mode = .stream });
    errdefer stream.close(rt.io);

    var rbuf: [1024]u8 = undefined;
    var wbuf: [4096]u8 = undefined;
    var reader = stream.reader(rt.io, &rbuf);
    var writer = stream.writer(rt.io, &wbuf);

    try writer.interface.print("CONNECT {s}:{d} HTTP/1.1\r\nHost: {s}:{d}\r\n", .{ target_host, target_port, target_host, target_port });
    switch (auth) {
        .none => {},
        .userpass => |up| {
            const creds = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ up.username, up.password });
            defer allocator.free(creds);
            const enc_len = std.base64.standard.Encoder.calcSize(creds.len);
            const enc = try allocator.alloc(u8, enc_len);
            defer allocator.free(enc);
            _ = std.base64.standard.Encoder.encode(enc, creds);
            try writer.interface.print("Proxy-Authorization: Basic {s}\r\n", .{enc});
        },
    }
    try writer.interface.writeAll("\r\n");
    try writer.interface.flush();

    var line_buf: [512]u8 = undefined;
    const line = try readLine(&reader.interface, &line_buf);
    if (!std.mem.startsWith(u8, line, "HTTP/1.")) return error.InvalidResponse;
    const sp = std.mem.indexOf(u8, line, " ") orelse return error.InvalidResponse;
    if (try std.fmt.parseInt(u16, line[sp + 1 ..][0..3], 10) != 200) return error.TunnelFailed;
    while (true) { const h = try readLine(&reader.interface, &line_buf); if (h.len == 0) break; }
    return stream;
}

fn readLine(reader: *std.Io.Reader, buf: []u8) ![]u8 {
    var i: usize = 0;
    while (i < buf.len) {
        const b = try reader.takeByte();
        if (b == '\r') { const n = try reader.takeByte(); if (n == '\n') return buf[0..i]; buf[i] = b; i += 1; buf[i] = n; i += 1; }
        else { buf[i] = b; i += 1; }
    }
    return error.LineTooLong;
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
