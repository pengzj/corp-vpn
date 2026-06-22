/// Embedded frontend assets baked into the binary at compile time.
/// Run `npm run build` in frontend/ before `zig build` to regenerate.
pub const index_html = @embedFile("www/index.html");
pub const index_js   = @embedFile("www/assets/index.js");
pub const index_css  = @embedFile("www/assets/index.css");
