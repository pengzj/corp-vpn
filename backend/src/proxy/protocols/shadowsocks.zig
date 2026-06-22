const std = @import("std");
const rt = @import("../../runtime.zig");

pub const Cipher = enum { aes_256_gcm, chacha20_poly1305 };

const KEY_SIZE = 32;
const SALT_SIZE = 32;
const TAG_SIZE = 16;


pub fn connect(
    allocator: std.mem.Allocator,
    proxy_host: []const u8,
    proxy_port: u16,
    password: []const u8,
    cipher: Cipher,
    target_host: []const u8,
    target_port: u16,
) !std.Io.net.Stream {
    const ip = std.Io.net.IpAddress.parse(proxy_host, proxy_port) catch
        try resolveDomain(allocator, proxy_host, proxy_port);
    const stream = try ip.connect(rt.io, .{ .mode = .stream });
    errdefer stream.close(rt.io);

    var master_key: [KEY_SIZE]u8 = undefined;
    deriveKey(password, &master_key);

    var enc_salt: [SALT_SIZE]u8 = undefined;
    rt.io.random(&enc_salt);

    var enc_key: [KEY_SIZE]u8 = undefined;
    hkdfDeriveSessionKey(&master_key, &enc_salt, "ss-subkey", &enc_key);
    var enc_nonce: [12]u8 = [_]u8{0} ** 12;

    // Send salt + encrypted target address header
    var wbuf: [4096]u8 = undefined;
    var writer = stream.writer(rt.io, &wbuf);
    try writer.interface.writeAll(&enc_salt);

    var addr_buf: [259]u8 = undefined;
    var addr_len: usize = 0;
    addr_buf[addr_len] = 0x03; addr_len += 1;
    addr_buf[addr_len] = @intCast(target_host.len); addr_len += 1;
    @memcpy(addr_buf[addr_len .. addr_len + target_host.len], target_host);
    addr_len += target_host.len;
    std.mem.writeInt(u16, addr_buf[addr_len .. addr_len + 2][0..2], target_port, .big);
    addr_len += 2;

    try writeChunkToWriter(&writer.interface, &enc_key, &enc_nonce, cipher, addr_buf[0..addr_len]);
    try writer.interface.flush();

    return stream;
}

fn writeChunkToWriter(writer: anytype, enc_key: *[KEY_SIZE]u8, enc_nonce: *[12]u8, cipher: Cipher, plaintext: []const u8) !void {
    var len_plain: [2]u8 = undefined;
    std.mem.writeInt(u16, &len_plain, @intCast(plaintext.len), .big);
    var len_cipher: [2 + TAG_SIZE]u8 = undefined;
    aeadEncrypt(cipher, enc_key.*, enc_nonce.*, &len_plain, &len_cipher);
    incrementNonce(enc_nonce);
    try writer.writeAll(&len_cipher);

    const payload = try std.heap.page_allocator.alloc(u8, plaintext.len + TAG_SIZE);
    defer std.heap.page_allocator.free(payload);
    aeadEncryptSlice(cipher, enc_key.*, enc_nonce.*, plaintext, payload);
    incrementNonce(enc_nonce);
    try writer.writeAll(payload);
}

fn deriveKey(password: []const u8, out: *[KEY_SIZE]u8) void {
    var d: [16]u8 = undefined;
    var d_prev: [16]u8 = undefined;
    var offset: usize = 0;
    var i: usize = 0;
    while (offset < KEY_SIZE) : (i += 1) {
        var h = std.crypto.hash.Md5.init(.{});
        if (i > 0) h.update(&d_prev);
        h.update(password);
        h.final(&d);
        d_prev = d;
        const n = @min(16, KEY_SIZE - offset);
        @memcpy(out[offset .. offset + n], d[0..n]);
        offset += n;
    }
}

fn hkdfDeriveSessionKey(master_key: *const [KEY_SIZE]u8, salt: *const [SALT_SIZE]u8, info: []const u8, out: *[KEY_SIZE]u8) void {
    var prk: [std.crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&prk, master_key, salt);
    var t: [std.crypto.auth.hmac.sha2.HmacSha256.mac_length]u8 = undefined;
    var offset: usize = 0;
    var counter: u8 = 1;
    while (offset < KEY_SIZE) {
        var hm = std.crypto.auth.hmac.sha2.HmacSha256.init(&prk);
        if (offset > 0) hm.update(&t);
        hm.update(info);
        hm.update(&[_]u8{counter});
        hm.final(&t);
        counter += 1;
        const n = @min(t.len, KEY_SIZE - offset);
        @memcpy(out[offset .. offset + n], t[0..n]);
        offset += n;
    }
}

fn aeadEncrypt(cipher: Cipher, key: [KEY_SIZE]u8, nonce: [12]u8, plain: []const u8, out: []u8) void {
    const tag = out[plain.len..][0..TAG_SIZE];
    switch (cipher) {
        .aes_256_gcm => std.crypto.aead.aes_gcm.Aes256Gcm.encrypt(out[0..plain.len], tag, plain, "", nonce, key),
        .chacha20_poly1305 => std.crypto.aead.chacha_poly.ChaCha20Poly1305.encrypt(out[0..plain.len], tag, plain, "", nonce, key),
    }
}

fn aeadEncryptSlice(cipher: Cipher, key: [KEY_SIZE]u8, nonce: [12]u8, plain: []const u8, out: []u8) void {
    const tag = out[plain.len..][0..TAG_SIZE];
    switch (cipher) {
        .aes_256_gcm => std.crypto.aead.aes_gcm.Aes256Gcm.encrypt(out[0..plain.len], tag, plain, "", nonce, key),
        .chacha20_poly1305 => std.crypto.aead.chacha_poly.ChaCha20Poly1305.encrypt(out[0..plain.len], tag, plain, "", nonce, key),
    }
}

fn incrementNonce(nonce: *[12]u8) void {
    var i: usize = 0;
    while (i < 12) : (i += 1) { nonce[i] +%= 1; if (nonce[i] != 0) break; }
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
