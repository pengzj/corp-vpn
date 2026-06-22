const std = @import("std");
const config = @import("config.zig");
const fe = @import("frontend.zig");
const rt = @import("runtime.zig");

const API_PORT: u16 = 7070;

pub fn run(allocator: std.mem.Allocator, cfg: *config.Config) !void {
    const ip = try std.Io.net.IpAddress.parse("0.0.0.0", API_PORT);
    var server = try ip.listen(rt.io, .{ .reuse_address = true });
    defer server.deinit(rt.io);
    std.log.info("Server on http://0.0.0.0:{d}", .{API_PORT});
    std.log.info("Open http://localhost:{d}", .{API_PORT});

    while (true) {
        const conn = server.accept(rt.io) catch |err| {
            std.log.warn("accept error: {}", .{err});
            continue;
        };
        const ctx = try allocator.create(HandlerCtx);
        ctx.* = .{ .conn = conn, .cfg = cfg, .allocator = allocator };
        const t = std.Thread.spawn(.{}, handleConn, .{ctx}) catch |err| {
            std.log.warn("spawn error: {}", .{err});
            conn.close(rt.io);
            allocator.destroy(ctx);
            continue;
        };
        t.detach();
    }
}

const HandlerCtx = struct {
    conn: std.Io.net.Stream,
    cfg: *config.Config,
    allocator: std.mem.Allocator,
};

fn handleConn(ctx: *HandlerCtx) void {
    defer ctx.allocator.destroy(ctx);
    defer ctx.conn.close(rt.io);
    handleConnInner(ctx) catch |err| std.log.debug("handler: {}", .{err});
}

fn handleConnInner(ctx: *HandlerCtx) !void {
    const allocator = ctx.allocator;

    var rbuf: [8192]u8 = undefined;
    var wbuf: [8192]u8 = undefined;
    var reader = ctx.conn.reader(rt.io, &rbuf);
    var writer = ctx.conn.writer(rt.io, &wbuf);

    var line_buf: [2048]u8 = undefined;
    const request_line = try readLine(&reader.interface, &line_buf);
    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = parts.next() orelse return;
    const raw_path = parts.next() orelse return;
    const path = if (std.mem.indexOfScalar(u8, raw_path, '?')) |q| raw_path[0..q] else raw_path;

    var content_length: usize = 0;
    var header_buf: [256]u8 = undefined;
    while (true) {
        const header = try readLine(&reader.interface, &header_buf);
        if (header.len == 0) break;
        if (std.ascii.startsWithIgnoreCase(header, "content-length:")) {
            const val = std.mem.trim(u8, header[15..], " ");
            content_length = std.fmt.parseInt(usize, val, 10) catch 0;
        }
    }

    var body: []u8 = &[_]u8{};
    defer if (body.len > 0) allocator.free(body);
    if (content_length > 0 and content_length < 64 * 1024) {
        body = try allocator.alloc(u8, content_length);
        try reader.interface.readSliceAll(body);
    }

    if (std.mem.eql(u8, method, "OPTIONS")) {
        try writer.interface.writeAll("HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Length: 0\r\n\r\n");
        try writer.interface.flush();
        return;
    }

    if (std.mem.eql(u8, method, "GET")) {
        if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html")) {
            try sendStatic(&writer, "text/html; charset=utf-8", fe.index_html);
            return;
        }
        if (std.mem.eql(u8, path, "/assets/index.js")) {
            try sendStatic(&writer, "application/javascript", fe.index_js);
            return;
        }
        if (std.mem.eql(u8, path, "/assets/index.css")) {
            try sendStatic(&writer, "text/css", fe.index_css);
            return;
        }
        if (!std.mem.startsWith(u8, path, "/api/")) {
            try sendStatic(&writer, "text/html; charset=utf-8", fe.index_html);
            return;
        }
    }

    var resp_buf: std.Io.Writer.Allocating = .init(allocator);
    defer resp_buf.deinit();
    var status: u16 = 200;

    if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/api/endpoints")) {
        try handleGetEndpoints(ctx.cfg, &resp_buf);
    } else if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, path, "/api/endpoints")) {
        status = try handleCreateEndpoint(allocator, ctx.cfg, body, &resp_buf);
    } else if (std.mem.eql(u8, method, "DELETE") and std.mem.startsWith(u8, path, "/api/endpoints/")) {
        status = try handleDeleteEndpoint(allocator, ctx.cfg, path["/api/endpoints/".len..], &resp_buf);
    } else if (std.mem.eql(u8, method, "PUT") and std.mem.startsWith(u8, path, "/api/endpoints/")) {
        status = try handleUpdateEndpoint(allocator, ctx.cfg, path["/api/endpoints/".len..], body, &resp_buf);
    } else if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/api/mode")) {
        try handleGetMode(ctx.cfg, &resp_buf);
    } else if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, path, "/api/mode")) {
        status = try handleSetMode(allocator, ctx.cfg, body, &resp_buf);
    } else if (std.mem.eql(u8, method, "POST") and std.mem.startsWith(u8, path, "/api/connect/")) {
        status = try handleConnect(allocator, ctx.cfg, path["/api/connect/".len..], &resp_buf);
    } else if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, path, "/api/disconnect")) {
        try handleDisconnect(allocator, ctx.cfg, &resp_buf);
    } else if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/api/status")) {
        try handleStatus(ctx.cfg, &resp_buf);
    } else {
        status = 404;
        try resp_buf.writer.writeAll("{\"error\":\"not found\"}");
    }

    try writer.interface.print("HTTP/1.1 {d} {s}\r\n", .{ status, statusText(status) });
    try writer.interface.writeAll("Content-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n");
    try writer.interface.print("Content-Length: {d}\r\n\r\n", .{resp_buf.written().len});
    try writer.interface.writeAll(resp_buf.written());
    try writer.interface.flush();
}

fn sendStatic(writer: anytype, content_type: []const u8, data: []const u8) !void {
    try writer.interface.print("HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nCache-Control: no-cache\r\nContent-Length: {d}\r\n\r\n", .{ content_type, data.len });
    try writer.interface.writeAll(data);
    try writer.interface.flush();
}

fn handleGetEndpoints(cfg: *config.Config, buf: *std.Io.Writer.Allocating) !void {
    cfg.mutex.lockUncancelable(rt.io);
    defer cfg.mutex.unlock(rt.io);
    try buf.writer.writeAll("[");
    for (cfg.endpoints.items, 0..) |ep, i| {
        try writeEndpointJson(&buf.writer, ep, cfg.active_endpoint_id);

        if (i < cfg.endpoints.items.len - 1) try buf.writer.writeAll(",");
    }
    try buf.writer.writeAll("]");
}

fn handleCreateEndpoint(allocator: std.mem.Allocator, cfg: *config.Config, body: []const u8, buf: *std.Io.Writer.Allocating) !u16 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return writeError(buf, "invalid json");
    defer parsed.deinit();
    const ep = parseEndpointFromJson(allocator, parsed.value.object) catch return writeError(buf, "missing or invalid fields");
    cfg.mutex.lockUncancelable(rt.io);
    defer cfg.mutex.unlock(rt.io);
    try cfg.endpoints.append(allocator, ep);
    try config.save(cfg, allocator);
    try writeEndpointJson(&buf.writer, ep, cfg.active_endpoint_id);
    return 201;
}

fn handleDeleteEndpoint(allocator: std.mem.Allocator, cfg: *config.Config, id: []const u8, buf: *std.Io.Writer.Allocating) !u16 {
    cfg.mutex.lockUncancelable(rt.io);
    defer cfg.mutex.unlock(rt.io);
    for (cfg.endpoints.items, 0..) |ep, i| {
        if (std.mem.eql(u8, ep.id, id)) {
            _ = cfg.endpoints.orderedRemove(i);
            freeEndpoint(allocator, ep);
            if (cfg.active_endpoint_id) |aid| if (std.mem.eql(u8, aid, id)) {
                allocator.free(cfg.active_endpoint_id.?);
                cfg.active_endpoint_id = null;
            };
            try config.save(cfg, allocator);
            try buf.writer.writeAll("{\"ok\":true}");
            return 200;
        }
    }
    return writeError(buf, "not found");
}

fn handleUpdateEndpoint(allocator: std.mem.Allocator, cfg: *config.Config, id: []const u8, body: []const u8, buf: *std.Io.Writer.Allocating) !u16 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return writeError(buf, "invalid json");
    defer parsed.deinit();
    cfg.mutex.lockUncancelable(rt.io);
    defer cfg.mutex.unlock(rt.io);
    for (cfg.endpoints.items) |*ep| {
        if (std.mem.eql(u8, ep.id, id)) {
            const obj = parsed.value.object;
            if (obj.get("label")) |v| if (v == .string) { allocator.free(ep.label); ep.label = try allocator.dupe(u8, v.string); };
            if (obj.get("enabled")) |v| if (v == .bool) { ep.enabled = v.bool; };
            try config.save(cfg, allocator);
            try writeEndpointJson(&buf.writer, ep.*, cfg.active_endpoint_id);
            return 200;
        }
    }
    return writeError(buf, "not found");
}

fn handleGetMode(cfg: *config.Config, buf: *std.Io.Writer.Allocating) !void {
    cfg.mutex.lockUncancelable(rt.io);
    defer cfg.mutex.unlock(rt.io);
    try buf.writer.print("{{\"mode\":\"{s}\"}}", .{cfg.mode.toString()});
}

fn handleSetMode(allocator: std.mem.Allocator, cfg: *config.Config, body: []const u8, buf: *std.Io.Writer.Allocating) !u16 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return writeError(buf, "invalid json");
    defer parsed.deinit();
    const mode_val = parsed.value.object.get("mode") orelse return writeError(buf, "missing mode");
    if (mode_val != .string) return writeError(buf, "mode must be string");
    const mode = config.Mode.fromString(mode_val.string) orelse return writeError(buf, "unknown mode");
    cfg.mutex.lockUncancelable(rt.io);
    defer cfg.mutex.unlock(rt.io);
    cfg.mode = mode;
    try config.save(cfg, allocator);
    try buf.writer.print("{{\"mode\":\"{s}\"}}", .{cfg.mode.toString()});
    return 200;
}

fn handleConnect(allocator: std.mem.Allocator, cfg: *config.Config, id: []const u8, buf: *std.Io.Writer.Allocating) !u16 {
    cfg.mutex.lockUncancelable(rt.io);
    defer cfg.mutex.unlock(rt.io);
    for (cfg.endpoints.items) |ep| {
        if (std.mem.eql(u8, ep.id, id)) {
            if (cfg.active_endpoint_id) |old| allocator.free(old);
            cfg.active_endpoint_id = try allocator.dupe(u8, id);
            if (cfg.mode == .off) cfg.mode = .global;
            try config.save(cfg, allocator);
            try buf.writer.print("{{\"active\":\"{s}\",\"mode\":\"{s}\"}}", .{ id, cfg.mode.toString() });
            return 200;
        }
    }
    return writeError(buf, "endpoint not found");
}

fn handleDisconnect(allocator: std.mem.Allocator, cfg: *config.Config, buf: *std.Io.Writer.Allocating) !void {
    cfg.mutex.lockUncancelable(rt.io);
    defer cfg.mutex.unlock(rt.io);
    if (cfg.active_endpoint_id) |id| { allocator.free(id); cfg.active_endpoint_id = null; }
    cfg.mode = .off;
    try config.save(cfg, allocator);
    try buf.writer.writeAll("{\"ok\":true}");
}

fn handleStatus(cfg: *config.Config, buf: *std.Io.Writer.Allocating) !void {
    cfg.mutex.lockUncancelable(rt.io);
    defer cfg.mutex.unlock(rt.io);
    try buf.writer.print("{{\"mode\":\"{s}\",\"endpoint_count\":{d},", .{ cfg.mode.toString(), cfg.endpoints.items.len });
    if (cfg.active_endpoint_id) |aid| try buf.writer.print("\"active_endpoint_id\":\"{s}\",", .{aid})
    else try buf.writer.writeAll("\"active_endpoint_id\":null,");
    try buf.writer.writeAll("\"local_socks5\":\"127.0.0.1:7890\",\"local_http\":\"127.0.0.1:7891\"}");
}

fn writeEndpointJson(w: *std.Io.Writer, ep: config.Endpoint, active_id: ?[]const u8) !void {
    const is_active = if (active_id) |aid| std.mem.eql(u8, aid, ep.id) else false;
    const auth_type = switch (ep.auth) { .none => "none", .userpass => "userpass", .shadowsocks => "shadowsocks" };
    try w.print("{{\"id\":\"{s}\",\"label\":\"{s}\",\"protocol\":\"{s}\",\"host\":\"{s}\",\"port\":{d},\"tls\":{s},\"enabled\":{s},\"active\":{s},\"auth_type\":\"{s}\"}}", .{
        ep.id, ep.label, ep.protocol.toString(), ep.host, ep.port,
        if (ep.tls) "true" else "false",
        if (ep.enabled) "true" else "false",
        if (is_active) "true" else "false",
        auth_type,
    });
}

fn writeError(buf: *std.Io.Writer.Allocating, msg: []const u8) !u16 {
    try buf.writer.print("{{\"error\":\"{s}\"}}", .{msg});
    return 400;
}

fn parseEndpointFromJson(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !config.Endpoint {
    const id = try config.generateId(allocator);
    errdefer allocator.free(id);
    const label = try allocator.dupe(u8, (obj.get("label") orelse return error.MissingField).string);
    errdefer allocator.free(label);
    const protocol = config.Protocol.fromString((obj.get("protocol") orelse return error.MissingField).string) orelse return error.UnknownProtocol;
    const host = try allocator.dupe(u8, (obj.get("host") orelse return error.MissingField).string);
    errdefer allocator.free(host);
    const port: u16 = @intCast((obj.get("port") orelse return error.MissingField).integer);
    const tls = if (obj.get("tls")) |v| v.bool else false;
    const enabled = if (obj.get("enabled")) |v| v.bool else true;
    const auth = try parseAuthFromJson(allocator, obj, protocol);
    return config.Endpoint{ .id = id, .label = label, .protocol = protocol, .host = host, .port = port, .auth = auth, .tls = tls, .enabled = enabled };
}

fn parseAuthFromJson(allocator: std.mem.Allocator, obj: std.json.ObjectMap, protocol: config.Protocol) !config.Auth {
    const auth_obj = obj.get("auth") orelse return config.Auth{ .none = {} };
    if (auth_obj != .object) return config.Auth{ .none = {} };
    const a = auth_obj.object;
    const auth_type = if (a.get("type")) |t| t.string else return config.Auth{ .none = {} };
    if (std.mem.eql(u8, auth_type, "userpass")) {
        const username = try allocator.dupe(u8, (a.get("username") orelse return error.MissingField).string);
        errdefer allocator.free(username);
        const password = try allocator.dupe(u8, (a.get("password") orelse return error.MissingField).string);
        return config.Auth{ .userpass = .{ .username = username, .password = password } };
    }
    if (std.mem.eql(u8, auth_type, "shadowsocks")) {
        _ = protocol;
        const password = try allocator.dupe(u8, (a.get("password") orelse return error.MissingField).string);
        errdefer allocator.free(password);
        const cipher = config.SsCipher.fromString((a.get("cipher") orelse return error.MissingField).string) orelse return error.UnknownCipher;
        return config.Auth{ .shadowsocks = .{ .password = password, .cipher = cipher } };
    }
    return config.Auth{ .none = {} };
}

fn freeEndpoint(allocator: std.mem.Allocator, ep: config.Endpoint) void {
    allocator.free(ep.id); allocator.free(ep.label); allocator.free(ep.host);
    switch (ep.auth) {
        .none => {},
        .userpass => |up| { allocator.free(up.username); allocator.free(up.password); },
        .shadowsocks => |ss| { allocator.free(ss.password); },
    }
}

fn statusText(code: u16) []const u8 {
    return switch (code) { 200 => "OK", 201 => "Created", 204 => "No Content", 400 => "Bad Request", 404 => "Not Found", 503 => "Service Unavailable", else => "Internal Server Error" };
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
