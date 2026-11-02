//! GTK4/Pango through the C shim (gtk_shim.h). GTK's own headers do not
//! survive translate-c with GLib 2.88, so the shim owns them and this module
//! exposes only the small C surface.

pub const c = @cImport({
    @cInclude("gtk_shim.h");
});
