#ifndef CADEX_GTK_SHIM_H
#define CADEX_GTK_SHIM_H

/* A small C surface over GTK4/Pango for the Zig app. The GTK headers do not
 * survive Zig's translate-c (GLib 2.88 uses _Pragma in declarations), so the
 * C compiler owns them and Zig sees only these prototypes. */

typedef void (*cadex_draw_fn)(void *ctx, int width, int height, void *user);
typedef int (*cadex_key_fn)(unsigned keyval, unsigned keycode, unsigned state, void *user);
typedef void (*cadex_commit_fn)(const char *text, void *user);
typedef void (*cadex_pointer_fn)(int x, int y, int button, unsigned state, int phase, int clicks, void *user);
typedef void (*cadex_scroll_fn)(double dx, double dy, void *user);
typedef void (*cadex_simple_fn)(void *user);
typedef void (*cadex_clipboard_fn)(const char *text, void *user);
typedef int (*cadex_close_fn)(void *user);

void *cadex_app_new(void);
void cadex_app_activate(void *app, void (*fn)(void *app, void *user), void *user);
int cadex_app_run(void *app);
int cadex_set_wayland(void);
void cadex_app_quit(void *app);

void *cadex_window_new(void *app, const char *title, int width, int height);
void *cadex_window_box(void *window);
void cadex_window_child(void *window, void *child);
void cadex_window_present(void *window, int background);
void cadex_window_title(void *window, const char *title);
void cadex_window_close(void *window);
void cadex_window_undecorated(void *window);
void cadex_window_on_close(void *window, cadex_close_fn fn, void *user);

void *cadex_header_new(void *window);
void *cadex_header_title(void *header, const char *text);
void cadex_header_set_title(void *label, const char *text);
void *cadex_header_button(void *header, const char *text, cadex_simple_fn fn, void *user);

void *cadex_box_new(void);
void cadex_box_append(void *box, void *child);
void cadex_widget_visible(void *widget, int visible);
void cadex_widget_focus(void *widget);
void cadex_widget_expand(void *widget);
void cadex_widget_size(void *widget, int *width, int *height);
void cadex_queue_draw(void *widget);

void *cadex_drawing_new(void);
void cadex_drawing_draw(void *area, cadex_draw_fn fn, void *user);
void cadex_drawing_input(void *area, cadex_key_fn key, cadex_commit_fn commit, void *user);
void cadex_drawing_mouse(void *area, cadex_pointer_fn pointer, cadex_scroll_fn scroll, void *user);
void cadex_im_focus(void *area, int focused);
void cadex_im_cursor(void *area, int x, int y, int w, int h);

void *cadex_entry_new(void);
void cadex_entry_changed(void *entry, cadex_simple_fn fn, void *user);
void cadex_entry_activate(void *entry, cadex_simple_fn fn, void *user);
void cadex_entry_escape(void *entry, cadex_simple_fn fn, void *user);
const char *cadex_entry_text(void *entry);
void cadex_entry_clear(void *entry);
void cadex_entry_select_all(void *entry);

void cadex_clipboard_set(void *widget, const char *text);
void cadex_clipboard_get(void *widget, cadex_clipboard_fn fn, void *user);
void cadex_beep(void *widget);

void cadex_idle(cadex_simple_fn fn, void *user);
void cadex_timeout(int ms, cadex_simple_fn fn, void *user);

/* Drawing context, created by the shim around each GtkDrawingArea frame. */
void cadex_draw_rect(void *ctx, double x, double y, double w, double h, unsigned rgb);
void cadex_draw_text(void *ctx, const char *text, int len, double x, double y, unsigned rgb, int bold, int italic);
void cadex_draw_line(void *ctx, double x1, double y1, double x2, double y2, unsigned rgb);
int cadex_text_metrics(void *area, const char *font, int *cell_w, int *cell_h, int *ascent);

unsigned cadex_keyval_unicode(unsigned keyval);
unsigned cadex_keyval_lower(unsigned keyval);
int cadex_utf8_encode(unsigned codepoint, char *out);

int cadex_open_uri(const char *uri);
int cadex_open_path(const char *path);

#endif
