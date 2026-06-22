const std = @import("std");
const config = @import("../config.zig");
const rt = @import("../runtime.zig");
const socks5_proto = @import("protocols/socks5.zig");
const http_proto = @import("protocols/http_connect.zig");
const ss_proto = @import("protocols/shadowsocks.zig");

pub const ProxyContext = struct {
    allocator: std.mem.Allocator,
    config: *config.Config,
};

const SOCKS5_PORT: u16 = 7890;
const HTTP_PORT: u16 = 7891;

pub fn runSocks5Listener(ctx: *ProxyContext) void {
    runSocks5Inner(ctx) catch |err| std.log.err("SOCKS5 listener: {}", .{err});
}

fn runSocks5Inner(ctx: *ProxyContext) !void {
    const ip = try std.Io.net.IpAddress.parse("127.0.0.1", SOCKS5_PORT);
    var server = try ip.listen(rt.io, .{ .reuse_address = true });
    defer server.deinit(rt.io);
    std.log.info("SOCKS5 ready on 127.0.0.1:{d}", .{SOCKS5_PORT});
    while (true) {
        const conn = server.accept(rt.io) catch |err| {
            std.log.warn("SOCKS5 accept: {}", .{err});
            continue;
        };
        const h = ctx.allocator.create(Socks5Handler) catch { conn.close(rt.io); continue; };
        h.* = .{ .conn = conn, .ctx = ctx };
        const t = std.Thread.spawn(.{}, handleSocks5, .{h}) catch {
            conn.close(rt.io);
            ctx.allocator.destroy(h);
            continue;
        };
        t.detach();
    }
}

const Socks5Handler = struct {
    conn: std.Io.net.Stream,
    ctx: *ProxyContext,
};

fn handleSocks5(h: *Socks5Handler) void {
    defer h.ctx.allocator.destroy(h);
    defer h.conn.close(rt.io);
    handleSocks5Inner(h) catch |err| std.log.debug("SOCKS5 conn: {}", .{err});
}

fn handleSocks5Inner(h: *Socks5Handler) !void {
    const allocator = h.ctx.allocator;

    var rbuf: [4096]u8 = undefined;
    var wbuf: [4096]u8 = undefined;
    var reader = h.conn.reader(rt.io, &rbuf);
    var writer = h.conn.writer(rt.io, &wbuf);

    const ver = try reader.interface.takeByte();
    if (ver != 0x05) return error.NotSocks5;
    const nmethods = try reader.interface.takeByte();
    var methods: [255]u8 = undefined;
    try reader.interface.readSliceAll(methods[0..nmethods]);
    try writer.interface.writeAll(&[_]u8{ 0x05, 0x00 });
    try writer.interface.flush();

    _ = try reader.interface.takeByte(); // VER
    const cmd = try reader.interface.takeByte();
    _ = try reader.interface.takeByte(); // RSV
    const atyp = try reader.interface.takeByte();
    if (cmd != 0x01) return error.OnlyCONNECT;

    var host_buf: [256]u8 = undefined;
    var target_host: []u8 = undefined;
    switch (atyp) {
        0x01 => { var ip4: [4]u8 = undefined; try reader.interface.readSliceAll(&ip4); target_host = try std.fmt.bufPrint(&host_buf, "{d}.{d}.{d}.{d}", .{ ip4[0], ip4[1], ip4[2], ip4[3] }); },
        0x03 => { const len = try reader.interface.takeByte(); try reader.interface.readSliceAll(host_buf[0..len]); target_host = host_buf[0..len]; },
        0x04 => { var ip6: [16]u8 = undefined; try reader.interface.readSliceAll(&ip6); target_host = try std.fmt.bufPrint(&host_buf, "{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}:{x:0>2}{x:0>2}", .{ ip6[0],ip6[1],ip6[2],ip6[3],ip6[4],ip6[5],ip6[6],ip6[7],ip6[8],ip6[9],ip6[10],ip6[11],ip6[12],ip6[13],ip6[14],ip6[15] }); },
        else => return error.UnknownAtyp,
    }
    const target_port = try reader.interface.takeInt(u16, .big);

    h.ctx.config.mutex.lockUncancelable(rt.io);
    const ep_opt = h.ctx.config.getActiveEndpoint();
    h.ctx.config.mutex.unlock(rt.io);

    const ep = ep_opt orelse {
        std.log.warn("SOCKS5 {s}:{d} → no active endpoint", .{ target_host, target_port });
        try writer.interface.writeAll(&[_]u8{ 0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0 });
        try writer.interface.flush();
        return error.NoActiveEndpoint;
    };

    std.log.info("SOCKS5 {s}:{d} → [{s}] {s}:{d}", .{ target_host, target_port, ep.protocol.toString(), ep.host, ep.port });

    const upstream = dialUpstream(allocator, ep, target_host, target_port) catch |err| {
        std.log.err("SOCKS5 {s}:{d} → upstream failed: {}", .{ target_host, target_port, err });
        try writer.interface.writeAll(&[_]u8{ 0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0 });
        try writer.interface.flush();
        return err;
    };
    defer upstream.close(rt.io);

    try writer.interface.writeAll(&[_]u8{ 0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0 });
    try writer.interface.flush();

    std.log.info("SOCKS5 {s}:{d} ✓ tunneling", .{ target_host, target_port });
    try pipe(allocator, h.conn, upstream);
    std.log.info("SOCKS5 {s}:{d} ✗ closed", .{ target_host, target_port });
}

pub fn runHttpListener(ctx: *ProxyContext) void {
    runHttpInner(ctx) catch |err| std.log.err("HTTP listener: {}", .{err});
}

fn runHttpInner(ctx: *ProxyContext) !void {
    const ip = try std.Io.net.IpAddress.parse("127.0.0.1", HTTP_PORT);
    var server = try ip.listen(rt.io, .{ .reuse_address = true });
    defer server.deinit(rt.io);
    std.log.info("HTTP proxy ready on 127.0.0.1:{d}", .{HTTP_PORT});
    while (true) {
        const conn = server.accept(rt.io) catch |err| {
            std.log.warn("HTTP accept: {}", .{err});
            continue;
        };
        const h = ctx.allocator.create(HttpHandler) catch { conn.close(rt.io); continue; };
        h.* = .{ .conn = conn, .ctx = ctx };
        const t = std.Thread.spawn(.{}, handleHttp, .{h}) catch {
            conn.close(rt.io);
            ctx.allocator.destroy(h);
            continue;
        };
        t.detach();
    }
}

const HttpHandler = struct {
    conn: std.Io.net.Stream,
    ctx: *ProxyContext,
};

fn handleHttp(h: *HttpHandler) void {
    defer h.ctx.allocator.destroy(h);
    defer h.conn.close(rt.io);
    handleHttpInner(h) catch |err| std.log.debug("HTTP conn: {}", .{err});
}

fn handleHttpInner(h: *HttpHandler) !void {
    const allocator = h.ctx.allocator;

    var rbuf: [4096]u8 = undefined;
    var wbuf: [4096]u8 = undefined;
    var reader = h.conn.reader(rt.io, &rbuf);
    var writer = h.conn.writer(rt.io, &wbuf);

    // Use separate buffers: line_buf for the CONNECT line, hdr_buf for headers.
    // hostport is a slice into line_buf — draining headers must NOT reuse line_buf.
    var line_buf: [1024]u8 = undefined;
    var hdr_buf: [1024]u8 = undefined;
    const line = try readLine(&reader.interface, &line_buf);
    var parts = std.mem.splitScalar(u8, line, ' ');
    const method = parts.next() orelse return error.BadRequest;
    const hostport = parts.next() orelse return error.BadRequest;

    if (!std.mem.eql(u8, method, "CONNECT")) {
        try writer.interface.writeAll("HTTP/1.1 405 Method Not Allowed\r\n\r\n");
        try writer.interface.flush();
        return error.OnlyCONNECT;
    }

    // Parse host:port BEFORE draining headers (which overwrites line_buf)
    const colon = std.mem.lastIndexOfScalar(u8, hostport, ':') orelse return error.BadRequest;
    const target_port = try std.fmt.parseInt(u16, hostport[colon + 1 ..], 10);
    // Copy host into its own buffer so it survives the header-drain loop
    var host_buf: [256]u8 = undefined;
    const host_len = colon;
    @memcpy(host_buf[0..host_len], hostport[0..host_len]);
    const target_host = host_buf[0..host_len];

    // Drain remaining headers into hdr_buf (not line_buf)
    while (true) { const hdr = try readLine(&reader.interface, &hdr_buf); if (hdr.len == 0) break; }

    h.ctx.config.mutex.lockUncancelable(rt.io);
    const ep_opt = h.ctx.config.getActiveEndpoint();
    h.ctx.config.mutex.unlock(rt.io);

    const ep = ep_opt orelse {
        std.log.warn("HTTP  {s}:{d} → no active endpoint", .{ target_host, target_port });
        try writer.interface.writeAll("HTTP/1.1 503 No Active Endpoint\r\n\r\n");
        try writer.interface.flush();
        return error.NoActiveEndpoint;
    };

    std.log.info("HTTP  {s}:{d} → [{s}] {s}:{d}", .{ target_host, target_port, ep.protocol.toString(), ep.host, ep.port });

    const upstream = dialUpstream(allocator, ep, target_host, target_port) catch |err| {
        std.log.err("HTTP  {s}:{d} → upstream failed: {}", .{ target_host, target_port, err });
        try writer.interface.writeAll("HTTP/1.1 502 Bad Gateway\r\n\r\n");
        try writer.interface.flush();
        return err;
    };
    defer upstream.close(rt.io);

    try writer.interface.writeAll("HTTP/1.1 200 Connection Established\r\n\r\n");
    try writer.interface.flush();

    std.log.info("HTTP  {s}:{d} ✓ tunneling", .{ target_host, target_port });
    try pipe(allocator, h.conn, upstream);
    std.log.info("HTTP  {s}:{d} ✗ closed", .{ target_host, target_port });
}

fn dialUpstream(allocator: std.mem.Allocator, ep: *config.Endpoint, target_host: []const u8, target_port: u16) !std.Io.net.Stream {
    switch (ep.protocol) {
        .socks5 => {
            const auth: socks5_proto.Socks5Auth = switch (ep.auth) {
                .userpass => |up| .{ .userpass = .{ .username = up.username, .password = up.password } },
                else => .{ .none = {} },
            };
            return try socks5_proto.connect(allocator, ep.host, ep.port, auth, target_host, target_port);
        },
        .http_connect => {
            const auth: http_proto.HttpAuth = switch (ep.auth) {
                .userpass => |up| .{ .userpass = .{ .username = up.username, .password = up.password } },
                else => .{ .none = {} },
            };
            return try http_proto.connect(allocator, ep.host, ep.port, auth, target_host, target_port);
        },
        .shadowsocks => {
            const ss_auth = switch (ep.auth) { .shadowsocks => |ss| ss, else => return error.MissingShadowsocksAuth };
            const cipher: ss_proto.Cipher = switch (ss_auth.cipher) {
                .aes_256_gcm => .aes_256_gcm,
                .chacha20_poly1305 => .chacha20_poly1305,
            };
            const ss_stream = try ss_proto.connect(allocator, ep.host, ep.port, ss_auth.password, cipher, target_host, target_port);
            return ss_stream;
        },
    }
}

const PipeCtx = struct { src: std.Io.net.Stream, dst: std.Io.net.Stream, done: *std.atomic.Value(bool) };

fn pipe(allocator: std.mem.Allocator, a: std.Io.net.Stream, b: std.Io.net.Stream) !void {
    var done = std.atomic.Value(bool).init(false);
    const ctx_b = try allocator.create(PipeCtx);
    ctx_b.* = .{ .src = b, .dst = a, .done = &done };
    defer allocator.destroy(ctx_b);
    const ctx_a = try allocator.create(PipeCtx);
    ctx_a.* = .{ .src = a, .dst = b, .done = &done };
    defer allocator.destroy(ctx_a);
    const t = try std.Thread.spawn(.{}, copyLoop, .{ctx_b});
    defer t.join();
    copyLoop(ctx_a);
}

fn copyLoop(ctx: *const PipeCtx) void {
    var rbuf: [4096]u8 = undefined;   // reader's internal read-ahead buffer
    var wbuf: [4096]u8 = undefined;   // writer's internal write buffer
    var data: [16384]u8 = undefined;  // separate transfer buffer — must not alias rbuf
    var reader = ctx.src.reader(rt.io, &rbuf);
    var writer = ctx.dst.writer(rt.io, &wbuf);
    while (!ctx.done.load(.acquire)) {
        const n = reader.interface.readSliceShort(&data) catch break;
        if (n == 0) break;
        writer.interface.writeAll(data[0..n]) catch break;
        writer.interface.flush() catch break;
    }
    ctx.done.store(true, .release);
}

fn readLine(reader: *std.Io.Reader, buf: []u8) ![]u8 {
    var i: usize = 0;
    while (i < buf.len) {
        const b = try reader.takeByte();
        if (b == '\r') {
            const next = try reader.takeByte();
            if (next == '\n') return buf[0..i];
            buf[i] = b; i += 1; buf[i] = next; i += 1;
        } else { buf[i] = b; i += 1; }
    }
    return error.LineTooLong;
}
