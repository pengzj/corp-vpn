const std = @import("std");
const runtime = @import("runtime.zig");
const config = @import("config.zig");
const api = @import("api.zig");
const local = @import("proxy/local.zig");

pub fn main(init: std.process.Init) !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    // Store the io provided by juicy main (Zig 0.16)
    runtime.io = init.io;

    var cfg = try config.load(allocator);
    defer cfg.deinit(allocator);

    std.log.info("ops_vpn starting...", .{});
    std.log.info("API + UI on http://localhost:7070", .{});
    std.log.info("SOCKS5 proxy on 127.0.0.1:7890", .{});
    std.log.info("HTTP  proxy on 127.0.0.1:7891", .{});

    const proxy_ctx = try allocator.create(local.ProxyContext);
    proxy_ctx.* = .{ .allocator = allocator, .config = &cfg };

    const t1 = try std.Thread.spawn(.{}, local.runSocks5Listener, .{proxy_ctx});
    t1.detach();
    const t2 = try std.Thread.spawn(.{}, local.runHttpListener, .{proxy_ctx});
    t2.detach();

    try api.run(allocator, &cfg);
}

