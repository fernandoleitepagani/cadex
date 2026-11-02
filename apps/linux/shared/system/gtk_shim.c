#include "gtk_shim.h"

#include <gtk/gtk.h>
#include <pango/pangocairo.h>
#include <string.h>

#define CADEX_FONT "Monospace 12"

typedef struct {
    GtkWidget *area;
    cairo_t *cr;
    PangoLayout *layout;
    PangoFontDescription *normal;
    PangoFontDescription *bold;
    PangoFontDescription *italic;
    PangoFontDescription *bold_italic;
} CadexDraw;

typedef struct {
    GtkWidget *area;
    GtkIMContext *im;
    cadex_key_fn key;
    cadex_commit_fn commit;
    void *user;
} CadexInput;

typedef struct {
    GtkWidget *area;
    cadex_pointer_fn pointer;
    cadex_scroll_fn scroll;
    void *user;
    int pressed;
    unsigned state;
} CadexMouse;

typedef struct {
    GtkWidget *area;
    cadex_draw_fn fn;
    void *user;
} CadexDrawCall;

typedef struct {
    cadex_simple_fn fn;
    void *user;
} CadexSimple;

typedef struct {
    cadex_clipboard_fn fn;
    void *user;
} CadexClip;

static void on_draw(GtkDrawingArea *area, cairo_t *cr, int width, int height, gpointer user) {
    CadexDrawCall *call = user;
    CadexDraw ctx = {0};
    ctx.area = GTK_WIDGET(area);
    ctx.cr = cr;
    ctx.layout = gtk_widget_create_pango_layout(ctx.area, NULL);
    ctx.normal = pango_font_description_from_string(CADEX_FONT);
    pango_layout_set_font_description(ctx.layout, ctx.normal);
    ctx.bold = pango_font_description_copy(ctx.normal);
    pango_font_description_set_weight(ctx.bold, PANGO_WEIGHT_BOLD);
    ctx.italic = pango_font_description_copy(ctx.normal);
    pango_font_description_set_style(ctx.italic, PANGO_STYLE_ITALIC);
    ctx.bold_italic = pango_font_description_copy(ctx.bold);
    pango_font_description_set_style(ctx.bold_italic, PANGO_STYLE_ITALIC);
    call->fn(&ctx, width, height, call->user);
    pango_font_description_free(ctx.bold_italic);
    pango_font_description_free(ctx.italic);
    pango_font_description_free(ctx.bold);
    pango_font_description_free(ctx.normal);
    g_object_unref(ctx.layout);
}

void cadex_draw_rect(void *ctx_ptr, double x, double y, double w, double h, unsigned rgb) {
    CadexDraw *ctx = ctx_ptr;
    cairo_set_source_rgb(ctx->cr, ((rgb >> 16) & 0xff) / 255.0, ((rgb >> 8) & 0xff) / 255.0, (rgb & 0xff) / 255.0);
    cairo_rectangle(ctx->cr, x, y, w, h);
    cairo_fill(ctx->cr);
}

void cadex_draw_text(void *ctx_ptr, const char *text, int len, double x, double y, unsigned rgb, int bold, int italic) {
    CadexDraw *ctx = ctx_ptr;
    if (len <= 0 || text == NULL) return;
    PangoFontDescription *font = ctx->normal;
    if (bold && italic) font = ctx->bold_italic;
    else if (bold) font = ctx->bold;
    else if (italic) font = ctx->italic;
    pango_layout_set_font_description(ctx->layout, font);
    pango_layout_set_text(ctx->layout, text, len);
    cairo_set_source_rgb(ctx->cr, ((rgb >> 16) & 0xff) / 255.0, ((rgb >> 8) & 0xff) / 255.0, (rgb & 0xff) / 255.0);
    cairo_move_to(ctx->cr, x, y);
    pango_cairo_show_layout(ctx->cr, ctx->layout);
}

void cadex_draw_line(void *ctx_ptr, double x1, double y1, double x2, double y2, unsigned rgb) {
    CadexDraw *ctx = ctx_ptr;
    cairo_set_source_rgb(ctx->cr, ((rgb >> 16) & 0xff) / 255.0, ((rgb >> 8) & 0xff) / 255.0, (rgb & 0xff) / 255.0);
    cairo_set_line_width(ctx->cr, 1.0);
    cairo_move_to(ctx->cr, x1, y1);
    cairo_line_to(ctx->cr, x2, y2);
    cairo_stroke(ctx->cr);
}

int cadex_text_metrics(void *area, const char *font, int *cell_w, int *cell_h, int *ascent) {
    GtkWidget *widget = area;
    PangoLayout *layout = gtk_widget_create_pango_layout(widget, NULL);
    PangoFontDescription *desc = pango_font_description_from_string(font);
    pango_layout_set_font_description(layout, desc);
    pango_layout_set_text(layout, "M", -1);
    int width = 0, height = 0;
    pango_layout_get_pixel_size(layout, &width, &height);
    PangoContext *pc = pango_layout_get_context(layout);
    PangoFontMetrics *metrics = pango_context_get_metrics(pc, desc, NULL);
    int asc = pango_font_metrics_get_ascent(metrics) / PANGO_SCALE;
    int dsc = pango_font_metrics_get_descent(metrics) / PANGO_SCALE;
    pango_font_metrics_unref(metrics);
    pango_font_description_free(desc);
    g_object_unref(layout);
    if (cell_w) *cell_w = width > 0 ? width : 8;
    if (cell_h) *cell_h = asc + dsc > 0 ? asc + dsc : height;
    if (ascent) *ascent = asc;
    return 1;
}

/* ---- App and window ---------------------------------------------------- */

void *cadex_app_new(void) {
    return gtk_application_new("io.github.c4duz.cadex", G_APPLICATION_NON_UNIQUE);
}

typedef struct {
    void (*fn)(void *app, void *user);
    void *user;
} CadexActivate;

static void on_activate(GtkApplication *app, gpointer user) {
    CadexActivate *activate = user;
    activate->fn(app, activate->user);
}

void cadex_app_activate(void *app, void (*fn)(void *app, void *user), void *user) {
    CadexActivate *activate = g_new0(CadexActivate, 1);
    activate->fn = fn;
    activate->user = user;
    g_signal_connect_data(app, "activate", G_CALLBACK(on_activate), activate, NULL, 0);
}

int cadex_set_wayland(void) {
    return g_setenv("GDK_BACKEND", "wayland", TRUE);
}

int cadex_app_run(void *app) {
    return g_application_run(G_APPLICATION(app), 0, NULL);
}

void cadex_app_quit(void *app) {
    g_application_quit(G_APPLICATION(app));
}

void *cadex_window_new(void *app, const char *title, int width, int height) {
    GtkWidget *window = gtk_application_window_new(GTK_APPLICATION(app));
    gtk_window_set_title(GTK_WINDOW(window), title);
    gtk_window_set_default_size(GTK_WINDOW(window), width, height);
    gtk_window_set_resizable(GTK_WINDOW(window), TRUE);
    return window;
}

void *cadex_window_box(void *window) {
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_window_set_child(GTK_WINDOW(window), box);
    return box;
}

void cadex_window_child(void *window, void *child) {
    gtk_window_set_child(GTK_WINDOW(window), GTK_WIDGET(child));
}

void cadex_window_present(void *window, int background) {
    if (background) gtk_window_set_focus_visible(GTK_WINDOW(window), FALSE);
    gtk_window_present(GTK_WINDOW(window));
}

void cadex_window_title(void *window, const char *title) {
    gtk_window_set_title(GTK_WINDOW(window), title);
}

void cadex_window_close(void *window) {
    gtk_window_close(GTK_WINDOW(window));
}

void cadex_window_undecorated(void *window) {
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
}

typedef struct {
    cadex_close_fn fn;
    void *user;
} CadexClose;

static gboolean on_close_request(GtkWindow *window, gpointer user) {
    (void)window;
    CadexClose *close = user;
    return close->fn(close->user) ? TRUE : FALSE;
}

void cadex_window_on_close(void *window, cadex_close_fn fn, void *user) {
    CadexClose *close = g_new0(CadexClose, 1);
    close->fn = fn;
    close->user = user;
    g_signal_connect_data(window, "close-request", G_CALLBACK(on_close_request), close, NULL, 0);
}

/* ---- Header bar -------------------------------------------------------- */

void *cadex_header_new(void *window) {
    GtkWidget *header = gtk_header_bar_new();
    gtk_window_set_titlebar(GTK_WINDOW(window), header);
    return header;
}

void *cadex_header_title(void *header, const char *text) {
    GtkWidget *label = gtk_label_new(text);
    gtk_header_bar_set_title_widget(GTK_HEADER_BAR(header), label);
    return label;
}

void cadex_header_set_title(void *label, const char *text) {
    gtk_label_set_text(GTK_LABEL(label), text);
}

static void on_button_clicked(GtkButton *button, gpointer user) {
    (void)button;
    CadexSimple *simple = user;
    simple->fn(simple->user);
}

void *cadex_header_button(void *header, const char *text, cadex_simple_fn fn, void *user) {
    GtkWidget *button = gtk_button_new_with_label(text);
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    g_signal_connect_data(button, "clicked", G_CALLBACK(on_button_clicked), simple, NULL, 0);
    gtk_header_bar_pack_end(GTK_HEADER_BAR(header), button);
    return button;
}

/* ---- Box and widgets --------------------------------------------------- */

void *cadex_box_new(void) {
    return gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
}

void cadex_box_append(void *box, void *child) {
    gtk_box_append(GTK_BOX(box), GTK_WIDGET(child));
}

void cadex_widget_visible(void *widget, int visible) {
    gtk_widget_set_visible(GTK_WIDGET(widget), visible ? TRUE : FALSE);
}

void cadex_widget_focus(void *widget) {
    gtk_widget_grab_focus(GTK_WIDGET(widget));
}

void cadex_widget_expand(void *widget) {
    gtk_widget_set_hexpand(GTK_WIDGET(widget), TRUE);
    gtk_widget_set_vexpand(GTK_WIDGET(widget), TRUE);
}

void cadex_widget_size(void *widget, int *width, int *height) {
    if (width) *width = gtk_widget_get_width(GTK_WIDGET(widget));
    if (height) *height = gtk_widget_get_height(GTK_WIDGET(widget));
}

void cadex_queue_draw(void *widget) {
    gtk_widget_queue_draw(GTK_WIDGET(widget));
}

void *cadex_drawing_new(void) {
    GtkWidget *area = gtk_drawing_area_new();
    gtk_widget_set_focusable(area, TRUE);
    return area;
}

void cadex_drawing_draw(void *area, cadex_draw_fn fn, void *user) {
    CadexDrawCall *call = g_new0(CadexDrawCall, 1);
    call->area = area;
    call->fn = fn;
    call->user = user;
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(area), on_draw, call, NULL);
}

static void im_commit(GtkIMContext *im, gchar *text, gpointer user) {
    (void)im;
    CadexInput *in = user;
    if (in->commit) in->commit(text, in->user);
}

static gboolean on_legacy_event(GtkEventControllerLegacy *controller, GdkEvent *event, gpointer user) {
    (void)controller;
    CadexInput *in = user;
    if (gdk_event_get_event_type(event) != GDK_KEY_PRESS) return FALSE;
    if (gtk_im_context_filter_keypress(in->im, event)) return TRUE;
    guint keyval = gdk_key_event_get_keyval(event);
    guint keycode = gdk_key_event_get_keycode(event);
    GdkModifierType state = gdk_event_get_modifier_state(event);
    if (in->key) return in->key(keyval, keycode, state, in->user) ? TRUE : FALSE;
    return FALSE;
}

static void on_focus_changed(GObject *object, GParamSpec *pspec, gpointer user) {
    (void)pspec;
    CadexInput *in = user;
    if (gtk_widget_has_focus(GTK_WIDGET(object))) gtk_im_context_focus_in(in->im);
    else gtk_im_context_focus_out(in->im);
}

void cadex_drawing_input(void *area, cadex_key_fn key, cadex_commit_fn commit, void *user) {
    CadexInput *in = g_new0(CadexInput, 1);
    in->area = area;
    in->key = key;
    in->commit = commit;
    in->user = user;
    in->im = gtk_im_multicontext_new();
    g_object_set_data(G_OBJECT(area), "cadex-im", in->im);
    gtk_im_context_set_client_widget(in->im, area);
    g_signal_connect_data(in->im, "commit", G_CALLBACK(im_commit), in, NULL, 0);
    g_signal_connect_data(area, "notify::has-focus", G_CALLBACK(on_focus_changed), in, NULL, 0);
    GtkEventController *legacy = gtk_event_controller_legacy_new();
    g_signal_connect_data(legacy, "event", G_CALLBACK(on_legacy_event), in, NULL, 0);
    gtk_widget_add_controller(GTK_WIDGET(area), legacy);
}

void cadex_im_focus(void *area, int focused) {
    GtkIMContext *im = g_object_get_data(G_OBJECT(area), "cadex-im");
    if (!im) return;
    if (focused) gtk_im_context_focus_in(im);
    else gtk_im_context_focus_out(im);
}

void cadex_im_cursor(void *area, int x, int y, int w, int h) {
    GtkIMContext *im = g_object_get_data(G_OBJECT(area), "cadex-im");
    if (!im) return;
    GdkRectangle rect = {x, y, w, h};
    gtk_im_context_set_cursor_location(im, &rect);
}

/* ---- Input: mouse ------------------------------------------------------ */

static unsigned current_state(GtkEventController *controller) {
    GdkEvent *event = gtk_event_controller_get_current_event(controller);
    GdkModifierType state = 0;
    if (event) state = gdk_event_get_modifier_state(event);
    return (unsigned)state;
}

static void on_click_pressed(GtkGestureClick *gesture, int n_press, double x, double y, gpointer user) {
    CadexMouse *mouse = user;
    mouse->pressed = 1;
    mouse->state = current_state(GTK_EVENT_CONTROLLER(gesture));
    if (mouse->pointer) mouse->pointer((int)x, (int)y, 1, mouse->state, 0, n_press, mouse->user);
}

static void on_click_released(GtkGestureClick *gesture, int n_press, double x, double y, gpointer user) {
    CadexMouse *mouse = user;
    mouse->pressed = 0;
    mouse->state = current_state(GTK_EVENT_CONTROLLER(gesture));
    if (mouse->pointer) mouse->pointer((int)x, (int)y, 1, mouse->state, 2, n_press, mouse->user);
}

static void on_motion(GtkEventControllerMotion *controller, double x, double y, gpointer user) {
    CadexMouse *mouse = user;
    if (!mouse->pressed) return;
    mouse->state = current_state(GTK_EVENT_CONTROLLER(controller));
    if (mouse->pointer) mouse->pointer((int)x, (int)y, 1, mouse->state, 1, 1, mouse->user);
}

static gboolean on_scroll(GtkEventControllerScroll *controller, double dx, double dy, gpointer user) {
    (void)controller;
    CadexMouse *mouse = user;
    if (mouse->scroll) mouse->scroll(dx, dy, mouse->user);
    return TRUE;
}

void cadex_drawing_mouse(void *area, cadex_pointer_fn pointer, cadex_scroll_fn scroll, void *user) {
    CadexMouse *mouse = g_new0(CadexMouse, 1);
    mouse->area = area;
    mouse->pointer = pointer;
    mouse->scroll = scroll;
    mouse->user = user;

    GtkGesture *click = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(click), 1);
    g_signal_connect_data(click, "pressed", G_CALLBACK(on_click_pressed), mouse, NULL, 0);
    g_signal_connect_data(click, "released", G_CALLBACK(on_click_released), mouse, NULL, 0);
    gtk_widget_add_controller(GTK_WIDGET(area), GTK_EVENT_CONTROLLER(click));

    GtkEventController *motion = gtk_event_controller_motion_new();
    g_signal_connect_data(motion, "motion", G_CALLBACK(on_motion), mouse, NULL, 0);
    gtk_widget_add_controller(GTK_WIDGET(area), motion);

    GtkEventController *scroll_ctl = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_VERTICAL);
    g_signal_connect_data(scroll_ctl, "scroll", G_CALLBACK(on_scroll), mouse, NULL, 0);
    gtk_widget_add_controller(GTK_WIDGET(area), scroll_ctl);
}

/* ---- Search entry ------------------------------------------------------ */

void *cadex_entry_new(void) {
    GtkWidget *entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(entry), "Find");
    gtk_widget_set_visible(entry, FALSE);
    return entry;
}

void cadex_entry_changed(void *entry, cadex_simple_fn fn, void *user) {
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    g_signal_connect_data(entry, "changed", G_CALLBACK(on_button_clicked), simple, NULL, 0);
}

void cadex_entry_activate(void *entry, cadex_simple_fn fn, void *user) {
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    g_signal_connect_data(entry, "activate", G_CALLBACK(on_button_clicked), simple, NULL, 0);
}

static gboolean on_entry_key(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer user) {
    (void)controller;
    (void)keycode;
    (void)state;
    CadexSimple *simple = user;
    if (keyval == GDK_KEY_Escape) {
        simple->fn(simple->user);
        return TRUE;
    }
    return FALSE;
}

void cadex_entry_escape(void *entry, cadex_simple_fn fn, void *user) {
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    GtkEventController *keys = gtk_event_controller_key_new();
    g_signal_connect_data(keys, "key-pressed", G_CALLBACK(on_entry_key), simple, NULL, 0);
    gtk_widget_add_controller(GTK_WIDGET(entry), keys);
}

const char *cadex_entry_text(void *entry) {
    return gtk_editable_get_text(GTK_EDITABLE(entry));
}

void cadex_entry_clear(void *entry) {
    gtk_editable_set_text(GTK_EDITABLE(entry), "");
}

void cadex_entry_select_all(void *entry) {
    gtk_editable_select_region(GTK_EDITABLE(entry), 0, -1);
}

/* ---- Clipboard, beep, idle -------------------------------------------- */

void cadex_clipboard_set(void *widget, const char *text) {
    GdkClipboard *clip = gtk_widget_get_clipboard(GTK_WIDGET(widget));
    gdk_clipboard_set_text(clip, text);
}

static void on_clipboard_text(GObject *source, GAsyncResult *result, gpointer user) {
    CadexClip *clip = user;
    GError *error = NULL;
    char *text = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(source), result, &error);
    if (clip->fn) clip->fn(text ? text : "", clip->user);
    g_free(text);
    if (error) g_error_free(error);
    g_free(clip);
}

void cadex_clipboard_get(void *widget, cadex_clipboard_fn fn, void *user) {
    CadexClip *clip = g_new0(CadexClip, 1);
    clip->fn = fn;
    clip->user = user;
    GdkClipboard *board = gtk_widget_get_clipboard(GTK_WIDGET(widget));
    gdk_clipboard_read_text_async(board, NULL, on_clipboard_text, clip);
}

void cadex_beep(void *widget) {
    GdkDisplay *display = gtk_widget_get_display(GTK_WIDGET(widget));
    if (display) gdk_display_beep(display);
}

static gboolean idle_cb(gpointer user) {
    CadexSimple *simple = user;
    simple->fn(simple->user);
    g_free(simple);
    return G_SOURCE_REMOVE;
}

void cadex_idle(cadex_simple_fn fn, void *user) {
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    g_idle_add(idle_cb, simple);
}

void cadex_timeout(int ms, cadex_simple_fn fn, void *user) {
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    g_timeout_add((guint)ms, idle_cb, simple);
}

/* ---- Keys and links ---------------------------------------------------- */

unsigned cadex_keyval_unicode(unsigned keyval) {
    return gdk_keyval_to_unicode(keyval);
}

unsigned cadex_keyval_lower(unsigned keyval) {
    return gdk_keyval_to_lower(keyval);
}

int cadex_utf8_encode(unsigned codepoint, char *out) {
    return g_unichar_to_utf8((gunichar)codepoint, out);
}

int cadex_open_uri(const char *uri) {
    return g_app_info_launch_default_for_uri(uri, NULL, NULL) ? 1 : 0;
}

int cadex_open_path(const char *path) {
    char *uri = g_filename_to_uri(path, NULL, NULL);
    if (!uri) return 0;
    int ok = g_app_info_launch_default_for_uri(uri, NULL, NULL) ? 1 : 0;
    g_free(uri);
    return ok;
}
