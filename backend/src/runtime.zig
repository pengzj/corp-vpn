/// Global std.Io for Zig 0.16.
/// Set once in main() from init.io (juicy main), read by all subsystems.
const std = @import("std");

pub var io: std.Io = undefined;
