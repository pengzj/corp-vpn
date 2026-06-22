const std = @import("std");
const R = std.Io.net.HostName.LookupResult;
comptime {
    @compileError(std.fmt.comptimePrint("{any}", .{std.meta.fields(R)}));
}
