const std = @import("std");

pub const Protocol = enum {
    socks5,
    http_connect,
    shadowsocks,

    pub fn fromString(s: []const u8) ?Protocol {
        if (std.mem.eql(u8, s, "socks5")) return .socks5;
        if (std.mem.eql(u8, s, "http_connect")) return .http_connect;
        if (std.mem.eql(u8, s, "shadowsocks")) return .shadowsocks;
        return null;
    }

    pub fn toString(self: Protocol) []const u8 {
        return switch (self) {
            .socks5 => "socks5",
            .http_connect => "http_connect",
            .shadowsocks => "shadowsocks",
        };
    }
};

pub const SsCipher = enum {
    aes_256_gcm,
    chacha20_poly1305,

    pub fn fromString(s: []const u8) ?SsCipher {
        if (std.mem.eql(u8, s, "aes-256-gcm")) return .aes_256_gcm;
        if (std.mem.eql(u8, s, "chacha20-poly1305")) return .chacha20_poly1305;
        return null;
    }

    pub fn toString(self: SsCipher) []const u8 {
        return switch (self) {
            .aes_256_gcm => "aes-256-gcm",
            .chacha20_poly1305 => "chacha20-poly1305",
        };
    }
};

pub const Auth = union(enum) {
    none: void,
    // SOCKS5 / HTTP CONNECT
    userpass: struct {
        username: []const u8,
        password: []const u8,
    },
    // Shadowsocks
    shadowsocks: struct {
        password: []const u8,
        cipher: SsCipher,
    },
};

pub const Endpoint = struct {
    id: []const u8,
    label: []const u8,
    protocol: Protocol,
    host: []const u8,
    port: u16,
    auth: Auth,
    tls: bool,
    enabled: bool,
};

pub const Mode = enum {
    off,
    global,
    local,

    pub fn fromString(s: []const u8) ?Mode {
        if (std.mem.eql(u8, s, "off")) return .off;
        if (std.mem.eql(u8, s, "global")) return .global;
        if (std.mem.eql(u8, s, "local")) return .local;
        return null;
    }

    pub fn toString(self: Mode) []const u8 {
        return switch (self) {
            .off => "off",
            .global => "global",
            .local => "local",
        };
    }
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    endpoints: std.ArrayList(Endpoint),
    mode: Mode,
    active_endpoint_id: ?[]const u8,
    mutex: std.Io.Mutex = .init,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        for (self.endpoints.items) |ep| {
            freeEndpoint(allocator, ep);
        }
        self.endpoints.deinit(allocator);
        if (self.active_endpoint_id) |id| {
            allocator.free(id);
        }
    }

    pub fn getActiveEndpoint(self: *Config) ?*Endpoint {
        const active_id = self.active_endpoint_id orelse return null;
        for (self.endpoints.items) |*ep| {
            if (std.mem.eql(u8, ep.id, active_id) and ep.enabled) {
                return ep;
            }
        }
        return null;
    }
};

fn freeEndpoint(allocator: std.mem.Allocator, ep: Endpoint) void {
    allocator.free(ep.id);
    allocator.free(ep.label);
    allocator.free(ep.host);
    switch (ep.auth) {
        .none => {},
        .userpass => |up| {
            allocator.free(up.username);
            allocator.free(up.password);
        },
        .shadowsocks => |ss| {
            allocator.free(ss.password);
        },
    }
}

const CONFIG_PATH = "data/config.json";

pub fn load(allocator: std.mem.Allocator) !Config {
    const io = @import("runtime.zig").io;

    var cfg = Config{
        .allocator = allocator,
        .endpoints = .empty,
        .mode = .off,
        .active_endpoint_id = null,
    };

    const cwd = std.Io.Dir.cwd();
    const content = cwd.readFileAlloc(io, CONFIG_PATH, allocator, .unlimited) catch |err| {
        if (err == error.FileNotFound) {
            try ensureDataDir(io);
            return cfg;
        }
        return err;
    };
    defer allocator.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch {
        std.log.warn("Failed to parse config.json, using defaults", .{});
        return cfg;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    // Parse mode
    if (root.get("mode")) |mode_val| {
        if (mode_val == .string) {
            cfg.mode = Mode.fromString(mode_val.string) orelse .off;
        }
    }

    // Parse active_endpoint_id
    if (root.get("active_endpoint_id")) |aid_val| {
        if (aid_val == .string) {
            cfg.active_endpoint_id = try allocator.dupe(u8, aid_val.string);
        }
    }

    // Parse endpoints
    if (root.get("endpoints")) |eps_val| {
        if (eps_val == .array) {
            for (eps_val.array.items) |ep_val| {
                if (ep_val != .object) continue;
                const ep = parseEndpoint(allocator, ep_val.object) catch continue;
                try cfg.endpoints.append(allocator, ep);
            }
        }
    }

    return cfg;
}

fn parseEndpoint(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Endpoint {
    const id = try allocator.dupe(u8, (obj.get("id") orelse return error.MissingField).string);
    errdefer allocator.free(id);

    const label = try allocator.dupe(u8, (obj.get("label") orelse return error.MissingField).string);
    errdefer allocator.free(label);

    const proto_str = (obj.get("protocol") orelse return error.MissingField).string;
    const protocol = Protocol.fromString(proto_str) orelse return error.UnknownProtocol;

    const host = try allocator.dupe(u8, (obj.get("host") orelse return error.MissingField).string);
    errdefer allocator.free(host);

    const port_val = obj.get("port") orelse return error.MissingField;
    const port: u16 = @intCast(port_val.integer);

    const tls = if (obj.get("tls")) |v| v.bool else false;
    const enabled = if (obj.get("enabled")) |v| v.bool else true;

    // Parse auth
    const auth = try parseAuth(allocator, obj, protocol);

    return Endpoint{
        .id = id,
        .label = label,
        .protocol = protocol,
        .host = host,
        .port = port,
        .auth = auth,
        .tls = tls,
        .enabled = enabled,
    };
}

fn parseAuth(allocator: std.mem.Allocator, obj: std.json.ObjectMap, protocol: Protocol) !Auth {
    const auth_obj = obj.get("auth") orelse return Auth{ .none = {} };
    if (auth_obj != .object) return Auth{ .none = {} };
    const a = auth_obj.object;

    const auth_type = if (a.get("type")) |t| t.string else return Auth{ .none = {} };

    if (std.mem.eql(u8, auth_type, "userpass")) {
        const username = try allocator.dupe(u8, (a.get("username") orelse return error.MissingField).string);
        errdefer allocator.free(username);
        const password = try allocator.dupe(u8, (a.get("password") orelse return error.MissingField).string);
        return Auth{ .userpass = .{ .username = username, .password = password } };
    }

    if (std.mem.eql(u8, auth_type, "shadowsocks")) {
        _ = protocol;
        const password = try allocator.dupe(u8, (a.get("password") orelse return error.MissingField).string);
        errdefer allocator.free(password);
        const cipher_str = (a.get("cipher") orelse return error.MissingField).string;
        const cipher = SsCipher.fromString(cipher_str) orelse return error.UnknownCipher;
        return Auth{ .shadowsocks = .{ .password = password, .cipher = cipher } };
    }

    return Auth{ .none = {} };
}

pub fn save(cfg: *Config, allocator: std.mem.Allocator) !void {
    const io = @import("runtime.zig").io;
    try ensureDataDir(io);

    var buf: std.Io.Writer.Allocating = .init(allocator);
    defer buf.deinit();

    try buf.writer.writeAll("{\n");
    try buf.writer.print("  \"mode\": \"{s}\",\n", .{cfg.mode.toString()});

    if (cfg.active_endpoint_id) |aid| {
        try buf.writer.print("  \"active_endpoint_id\": \"{s}\",\n", .{aid});
    } else {
        try buf.writer.writeAll("  \"active_endpoint_id\": null,\n");
    }

    try buf.writer.writeAll("  \"endpoints\": [\n");
    for (cfg.endpoints.items, 0..) |ep, i| {
        try writeEndpointJson(&buf.writer, ep);
        if (i < cfg.endpoints.items.len - 1) try buf.writer.writeAll(",");
        try buf.writer.writeAll("\n");
    }
    try buf.writer.writeAll("  ]\n}\n");

    const cwd = std.Io.Dir.cwd();
    const file = try cwd.createFile(io, CONFIG_PATH, .{});
    defer file.close(io);
    var wbuf: [8192]u8 = undefined;
    var fw = file.writer(io, &wbuf);
    try fw.interface.writeAll(buf.written());
    try fw.interface.flush();
}

fn writeEndpointJson(writer: *std.Io.Writer, ep: Endpoint) !void {
    try writer.writeAll("    {\n");
    try writer.print("      \"id\": \"{s}\",\n", .{ep.id});
    try writer.print("      \"label\": \"{s}\",\n", .{ep.label});
    try writer.print("      \"protocol\": \"{s}\",\n", .{ep.protocol.toString()});
    try writer.print("      \"host\": \"{s}\",\n", .{ep.host});
    try writer.print("      \"port\": {d},\n", .{ep.port});
    try writer.print("      \"tls\": {s},\n", .{if (ep.tls) "true" else "false"});
    try writer.print("      \"enabled\": {s},\n", .{if (ep.enabled) "true" else "false"});

    switch (ep.auth) {
        .none => try writer.writeAll("      \"auth\": {\"type\": \"none\"}\n"),
        .userpass => |up| {
            try writer.print("      \"auth\": {{\"type\": \"userpass\", \"username\": \"{s}\", \"password\": \"{s}\"}}\n", .{ up.username, up.password });
        },
        .shadowsocks => |ss| {
            try writer.print("      \"auth\": {{\"type\": \"shadowsocks\", \"password\": \"{s}\", \"cipher\": \"{s}\"}}\n", .{ ss.password, ss.cipher.toString() });
        },
    }
    try writer.writeAll("    }");
}

fn ensureDataDir(io: std.Io) !void {
    std.Io.Dir.cwd().createDir(io, "data", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

pub fn generateId(allocator: std.mem.Allocator) ![]u8 {
    const io = @import("runtime.zig").io;
    var buf: [16]u8 = undefined;
    io.random(&buf);
    return std.fmt.allocPrint(allocator, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
        buf[0], buf[1], buf[2],  buf[3],
        buf[4], buf[5],
        buf[6], buf[7],
        buf[8], buf[9],
        buf[10], buf[11], buf[12], buf[13], buf[14], buf[15],
    });
}
