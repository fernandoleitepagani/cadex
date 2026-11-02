#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include "gtk_shim.h"

#include <gtk/gtk.h>
#ifdef CADEX_HAS_ADW
#include <adwaita.h>
#endif
#include <glib/gstdio.h>
#include <signal.h>
#include <sys/stat.h>
#include <pango/pangocairo.h>
#include <string.h>

static char cadex_font[64] = "Monospace 12";

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
    ctx.normal = pango_font_description_from_string(cadex_font);
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
#ifdef CADEX_HAS_ADW
    adw_init();
#endif
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
#ifdef CADEX_HAS_ADW
    GtkWidget *window = adw_application_window_new(GTK_APPLICATION(app));
#else
    GtkWidget *window = gtk_application_window_new(GTK_APPLICATION(app));
#endif
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
#ifdef CADEX_HAS_ADW
    GtkWidget *toolbar = adw_toolbar_view_new();
    adw_application_window_set_content(ADW_APPLICATION_WINDOW(window), toolbar);
    g_object_set_data(G_OBJECT(window), "cadex-toolbar", toolbar);
#endif
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
#ifdef CADEX_HAS_ADW
    GtkWidget *toolbar = g_object_get_data(G_OBJECT(window), "cadex-toolbar");
    if (toolbar) {
        adw_toolbar_view_set_content(ADW_TOOLBAR_VIEW(toolbar), GTK_WIDGET(child));
        return;
    }
#endif
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
#ifdef CADEX_HAS_ADW
    GtkWidget *toolbar = g_object_get_data(G_OBJECT(window), "cadex-toolbar");
    if (toolbar) {
        GtkWidget *header = adw_header_bar_new();
        adw_toolbar_view_add_top_bar(ADW_TOOLBAR_VIEW(toolbar), header);
        return header;
    }
#endif
    GtkWidget *header = gtk_header_bar_new();
    gtk_widget_set_visible(header, TRUE);
    gtk_window_set_titlebar(GTK_WINDOW(window), header);
    return header;
}

void *cadex_header_title(void *header, const char *text) {
#ifdef CADEX_HAS_ADW
    GtkWidget *title = adw_window_title_new(text, NULL);
    adw_header_bar_set_title_widget(ADW_HEADER_BAR(header), title);
    return title;
#else
    GtkWidget *label = gtk_label_new(text);
    gtk_header_bar_set_title_widget(GTK_HEADER_BAR(header), label);
    return label;
#endif
}

void cadex_header_set_title(void *label, const char *text) {
#ifdef CADEX_HAS_ADW
    if (ADW_IS_WINDOW_TITLE(label)) {
        adw_window_title_set_title(ADW_WINDOW_TITLE(label), text);
        return;
    }
#endif
    gtk_label_set_text(GTK_LABEL(label), text);
}

void cadex_header_set_subtitle(void *label, const char *text) {
#ifdef CADEX_HAS_ADW
    if (ADW_IS_WINDOW_TITLE(label)) {
        adw_window_title_set_subtitle(ADW_WINDOW_TITLE(label), text);
        return;
    }
#endif
    (void)label; (void)text;
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
#ifdef CADEX_HAS_ADW
    #ifdef CADEX_HAS_ADW
    adw_header_bar_pack_end(ADW_HEADER_BAR(header), button);
#else
    gtk_header_bar_pack_end(GTK_HEADER_BAR(header), button);
#endif
#else
    #ifdef CADEX_HAS_ADW
    adw_header_bar_pack_end(ADW_HEADER_BAR(header), button);
#else
    gtk_header_bar_pack_end(GTK_HEADER_BAR(header), button);
#endif
#endif
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

void cadex_widget_expand_h(void *widget) {
    gtk_widget_set_hexpand(GTK_WIDGET(widget), TRUE);
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

/* ---- Shell widgets (Run 3) -------------------------------------------- */

void *cadex_box_new_h(int spacing) {
    return gtk_box_new(GTK_ORIENTATION_HORIZONTAL, spacing);
}

#ifdef CADEX_HAS_ADW
static GtkWidget *notebook_view(void *notebook) {
    return g_object_get_data(G_OBJECT(notebook), "cadex-tab-view");
}

static const char *tab_label_text(GtkWidget *label) {
    if (!label) return "";
    if (GTK_IS_LABEL(label)) return gtk_label_get_text(GTK_LABEL(label));
    GtkWidget *child = gtk_widget_get_first_child(label);
    while (child) {
        if (GTK_IS_LABEL(child)) return gtk_label_get_text(GTK_LABEL(child));
        child = gtk_widget_get_next_sibling(child);
    }
    return "";
}

static int page_position(AdwTabView *view, AdwTabPage *page) {
    if (!page) return -1;
    return adw_tab_view_get_page_position(view, page);
}
#endif

void *cadex_notebook_new(void) {
#ifdef CADEX_HAS_ADW
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_set_vexpand(box, TRUE);
    gtk_widget_set_hexpand(box, TRUE);
    GtkWidget *view = GTK_WIDGET(adw_tab_view_new());
    GtkWidget *bar = GTK_WIDGET(adw_tab_bar_new());
    adw_tab_bar_set_view(ADW_TAB_BAR(bar), ADW_TAB_VIEW(view));
    adw_tab_bar_set_autohide(ADW_TAB_BAR(bar), TRUE);
    adw_tab_bar_set_expand_tabs(ADW_TAB_BAR(bar), FALSE);
    gtk_widget_set_hexpand(bar, TRUE);
    gtk_box_append(GTK_BOX(box), bar);
    gtk_widget_set_vexpand(view, TRUE);
    gtk_box_append(GTK_BOX(box), view);
    g_object_set_data(G_OBJECT(box), "cadex-tab-view", view);
    return box;
#else
    GtkWidget *notebook = gtk_notebook_new();
    gtk_notebook_set_show_border(GTK_NOTEBOOK(notebook), FALSE);
    gtk_notebook_set_scrollable(GTK_NOTEBOOK(notebook), TRUE);
    return notebook;
#endif
}

void cadex_notebook_append(void *notebook, void *page, void *label) {
#ifdef CADEX_HAS_ADW
    AdwTabView *view = ADW_TAB_VIEW(notebook_view(notebook));
    AdwTabPage *tab = adw_tab_view_append(view, GTK_WIDGET(page));
    if (tab) adw_tab_page_set_title(tab, tab_label_text(label));
#else
    gtk_notebook_append_page(GTK_NOTEBOOK(notebook), GTK_WIDGET(page), label ? GTK_WIDGET(label) : NULL);
#endif
}

void cadex_notebook_insert(void *notebook, int index, void *page, void *label) {
#ifdef CADEX_HAS_ADW
    AdwTabView *view = ADW_TAB_VIEW(notebook_view(notebook));
    AdwTabPage *tab = adw_tab_view_insert(view, GTK_WIDGET(page), index);
    if (tab) adw_tab_page_set_title(tab, tab_label_text(label));
#else
    gtk_notebook_insert_page(GTK_NOTEBOOK(notebook), GTK_WIDGET(page), label ? GTK_WIDGET(label) : NULL, index);
#endif
}

void cadex_notebook_remove(void *notebook, int index) {
#ifdef CADEX_HAS_ADW
    AdwTabView *view = ADW_TAB_VIEW(notebook_view(notebook));
    AdwTabPage *page = adw_tab_view_get_nth_page(view, index);
    if (!page) return;
    adw_tab_view_close_page(view, page);
#else
    gtk_notebook_remove_page(GTK_NOTEBOOK(notebook), index);
#endif
}

int cadex_notebook_page_num(void *notebook, void *page) {
#ifdef CADEX_HAS_ADW
    AdwTabView *view = ADW_TAB_VIEW(notebook_view(notebook));
    return page_position(view, adw_tab_view_get_page(view, GTK_WIDGET(page)));
#else
    return gtk_notebook_page_num(GTK_NOTEBOOK(notebook), GTK_WIDGET(page));
#endif
}

int cadex_notebook_current(void *notebook) {
#ifdef CADEX_HAS_ADW
    AdwTabView *view = ADW_TAB_VIEW(notebook_view(notebook));
    return page_position(view, adw_tab_view_get_selected_page(view));
#else
    return gtk_notebook_get_current_page(GTK_NOTEBOOK(notebook));
#endif
}

void cadex_notebook_set_current(void *notebook, int index) {
#ifdef CADEX_HAS_ADW
    AdwTabView *view = ADW_TAB_VIEW(notebook_view(notebook));
    AdwTabPage *page = adw_tab_view_get_nth_page(view, index);
    if (page) adw_tab_view_set_selected_page(view, page);
#else
    gtk_notebook_set_current_page(GTK_NOTEBOOK(notebook), index);
#endif
}

int cadex_notebook_count(void *notebook) {
#ifdef CADEX_HAS_ADW
    return (int)adw_tab_view_get_n_pages(ADW_TAB_VIEW(notebook_view(notebook)));
#else
    return gtk_notebook_get_n_pages(GTK_NOTEBOOK(notebook));
#endif
}

void *cadex_notebook_page(void *notebook, int index) {
#ifdef CADEX_HAS_ADW
    AdwTabPage *page = adw_tab_view_get_nth_page(ADW_TAB_VIEW(notebook_view(notebook)), index);
    return page ? adw_tab_page_get_child(page) : NULL;
#else
    return gtk_notebook_get_nth_page(GTK_NOTEBOOK(notebook), index);
#endif
}

typedef struct {
    void (*fn)(void *notebook, int index, void *user);
    void *notebook;
    void *user;
} CadexNotebookSwitch;

#ifdef CADEX_HAS_ADW
static void on_notebook_switch(GObject *object, GParamSpec *pspec, gpointer user) {
    (void)pspec;
    CadexNotebookSwitch *sw = user;
    AdwTabView *view = ADW_TAB_VIEW(object);
    AdwTabPage *page = adw_tab_view_get_selected_page(view);
    sw->fn(sw->notebook, page_position(view, page), sw->user);
}
#else
static void on_notebook_switch(GtkNotebook *notebook, GtkWidget *page, guint index, gpointer user) {
    (void)page;
    CadexNotebookSwitch *sw = user;
    sw->fn(notebook, (int)index, sw->user);
}
#endif

void cadex_notebook_on_switch(void *notebook, void (*fn)(void *notebook, int index, void *user), void *user) {
    CadexNotebookSwitch *sw = g_new0(CadexNotebookSwitch, 1);
    sw->fn = fn;
    sw->notebook = notebook;
    sw->user = user;
#ifdef CADEX_HAS_ADW
    g_signal_connect_data(notebook_view(notebook), "notify::selected-page", G_CALLBACK(on_notebook_switch), sw, NULL, 0);
#else
    g_signal_connect_data(notebook, "switch-page", G_CALLBACK(on_notebook_switch), sw, NULL, 0);
#endif
}

void cadex_notebook_size(void *notebook, int *w, int *h) {
#ifdef CADEX_HAS_ADW
    GtkWidget *view = notebook_view(notebook);
    if (w) *w = gtk_widget_get_width(view);
    if (h) *h = gtk_widget_get_height(view);
#else
    (void)notebook; (void)w; (void)h;
#endif
}

void cadex_notebook_set_title(void *notebook, void *child, const char *title) {
#ifdef CADEX_HAS_ADW
    AdwTabView *view = ADW_TAB_VIEW(notebook_view(notebook));
    AdwTabPage *page = adw_tab_view_get_page(view, GTK_WIDGET(child));
    if (page) adw_tab_page_set_title(page, title);
#else
    (void)notebook; (void)child; (void)title;
#endif
}

typedef struct {
    void (*fn)(void *child, void *user);
    void *user;
} CadexNotebookClose;

#ifdef CADEX_HAS_ADW
static gboolean on_notebook_close(AdwTabView *view, AdwTabPage *page, gpointer user) {
    CadexNotebookClose *close = user;
    GtkWidget *child = adw_tab_page_get_child(page);
    close->fn(child, close->user);
    (void)view;
    return FALSE;
}
#endif

void cadex_notebook_on_close(void *notebook, void (*fn)(void *child, void *user), void *user) {
#ifdef CADEX_HAS_ADW
    CadexNotebookClose *close = g_new0(CadexNotebookClose, 1);
    close->fn = fn;
    close->user = user;
    g_signal_connect_data(notebook_view(notebook), "close-page", G_CALLBACK(on_notebook_close), close, NULL, 0);
#else
    (void)notebook; (void)fn; (void)user;
#endif
}

void *cadex_paned_new(int orientation) {
    return gtk_paned_new(orientation ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL);
}

void cadex_paned_set_start(void *paned, void *child) {
    gtk_paned_set_start_child(GTK_PANED(paned), child ? GTK_WIDGET(child) : NULL);
}

void cadex_paned_set_end(void *paned, void *child) {
    gtk_paned_set_end_child(GTK_PANED(paned), child ? GTK_WIDGET(child) : NULL);
}

void cadex_paned_set_position(void *paned, int position) {
    gtk_paned_set_position(GTK_PANED(paned), position);
}

void *cadex_stack_new(void) {
#ifdef CADEX_HAS_ADW
    return adw_view_stack_new();
#else
    return gtk_stack_new();
#endif
}

void cadex_stack_add(void *stack, void *child, const char *name) {
#ifdef CADEX_HAS_ADW
    AdwViewStackPage *page = adw_view_stack_add_named(ADW_VIEW_STACK(stack), GTK_WIDGET(child), name);
    if (page) adw_view_stack_page_set_title(page, name);
#else
    gtk_stack_add_named(GTK_STACK(stack), GTK_WIDGET(child), name);
#endif
}

void cadex_stack_set(void *stack, const char *name) {
#ifdef CADEX_HAS_ADW
    adw_view_stack_set_visible_child_name(ADW_VIEW_STACK(stack), name);
#else
    gtk_stack_set_visible_child_name(GTK_STACK(stack), name);
#endif
}

typedef struct {
    void (*fn)(const char *name, void *user);
    void *user;
} CadexStackSwitch;

#ifdef CADEX_HAS_ADW
static void on_stack_changed(GObject *object, GParamSpec *pspec, gpointer user) {
    (void)pspec;
    CadexStackSwitch *sw = user;
    const char *name = adw_view_stack_get_visible_child_name(ADW_VIEW_STACK(object));
    if (name) sw->fn(name, sw->user);
}
#endif

void cadex_stack_on_changed(void *stack, void (*fn)(const char *name, void *user), void *user) {
#ifdef CADEX_HAS_ADW
    CadexStackSwitch *sw = g_new0(CadexStackSwitch, 1);
    sw->fn = fn;
    sw->user = user;
    g_signal_connect_data(stack, "notify::visible-child", G_CALLBACK(on_stack_changed), sw, NULL, 0);
#else
    (void)stack; (void)fn; (void)user;
#endif
}

void *cadex_label_new(const char *text) {
    return gtk_label_new(text);
}

void cadex_label_set(void *label, const char *text) {
    gtk_label_set_text(GTK_LABEL(label), text);
}

void cadex_label_ellipsize(void *label) {
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
}

void cadex_label_set_xalign(void *label, double align) {
    gtk_label_set_xalign(GTK_LABEL(label), (float)align);
}

void *cadex_button_new(const char *text, void (*fn)(void *), void *user) {
    GtkWidget *button = gtk_button_new_with_label(text);
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    g_signal_connect_data(button, "clicked", G_CALLBACK(on_button_clicked), simple, NULL, 0);
    return button;
}

void cadex_text_set_font(const char *font) {
    g_strlcpy(cadex_font, font, sizeof(cadex_font));
}

void cadex_header_widget_start(void *header, void *widget) {
#ifdef CADEX_HAS_ADW
    #ifdef CADEX_HAS_ADW
    adw_header_bar_pack_start(ADW_HEADER_BAR(header), GTK_WIDGET(widget));
#else
    gtk_header_bar_pack_start(GTK_HEADER_BAR(header), GTK_WIDGET(widget));
#endif
#else
    #ifdef CADEX_HAS_ADW
    adw_header_bar_pack_start(ADW_HEADER_BAR(header), GTK_WIDGET(widget));
#else
    gtk_header_bar_pack_start(GTK_HEADER_BAR(header), GTK_WIDGET(widget));
#endif
#endif
}

void cadex_header_widget_end(void *header, void *widget) {
#ifdef CADEX_HAS_ADW
    #ifdef CADEX_HAS_ADW
    adw_header_bar_pack_end(ADW_HEADER_BAR(header), GTK_WIDGET(widget));
#else
    gtk_header_bar_pack_end(GTK_HEADER_BAR(header), GTK_WIDGET(widget));
#endif
#else
    #ifdef CADEX_HAS_ADW
    adw_header_bar_pack_end(ADW_HEADER_BAR(header), GTK_WIDGET(widget));
#else
    gtk_header_bar_pack_end(GTK_HEADER_BAR(header), GTK_WIDGET(widget));
#endif
#endif
}

void cadex_button_set_text(void *button, const char *text) {
    gtk_button_set_label(GTK_BUTTON(button), text);
}

void *cadex_header_button_start(void *header, const char *text, cadex_simple_fn fn, void *user) {
    GtkWidget *button = gtk_button_new_with_label(text);
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    g_signal_connect_data(button, "clicked", G_CALLBACK(on_button_clicked), simple, NULL, 0);
#ifdef CADEX_HAS_ADW
    #ifdef CADEX_HAS_ADW
    adw_header_bar_pack_start(ADW_HEADER_BAR(header), button);
#else
    gtk_header_bar_pack_start(GTK_HEADER_BAR(header), button);
#endif
#else
    #ifdef CADEX_HAS_ADW
    adw_header_bar_pack_start(ADW_HEADER_BAR(header), button);
#else
    gtk_header_bar_pack_start(GTK_HEADER_BAR(header), button);
#endif
#endif
    return button;
}

void *cadex_listbox_new(void) {
    GtkWidget *box = gtk_list_box_new();
    gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(box), TRUE);
    return box;
}

void cadex_listbox_clear(void *box) {
    GtkWidget *child = gtk_widget_get_first_child(GTK_WIDGET(box));
    while (child) {
        GtkWidget *next = gtk_widget_get_next_sibling(child);
        gtk_list_box_remove(GTK_LIST_BOX(box), child);
        child = next;
    }
}

void cadex_listbox_append(void *box, const char *text) {
    GtkWidget *row = gtk_list_box_row_new();
    GtkWidget *label = gtk_label_new(text);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), label);
    gtk_list_box_append(GTK_LIST_BOX(box), row);
}

typedef struct {
    void (*fn)(int index, void *user);
    void *user;
} CadexListActivate;

static void on_row_activated(GtkListBox *box, GtkListBoxRow *row, gpointer user) {
    (void)box;
    CadexListActivate *activate = user;
    activate->fn(gtk_list_box_row_get_index(row), activate->user);
}

void cadex_listbox_on_activated(void *box, void (*fn)(int index, void *user), void *user) {
    CadexListActivate *activate = g_new0(CadexListActivate, 1);
    activate->fn = fn;
    activate->user = user;
    g_signal_connect_data(box, "row-activated", G_CALLBACK(on_row_activated), activate, NULL, 0);
}

void *cadex_scrolled_new(void *child) {
    GtkWidget *scrolled = gtk_scrolled_window_new();
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scrolled), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scrolled), child ? GTK_WIDGET(child) : NULL);
    return scrolled;
}

void *cadex_dropdown_new(const char *const *items, int count) {
    const char **copy = g_new0(const char *, (gsize)count + 1);
    for (int i = 0; i < count; i++) copy[i] = items[i];
    GtkWidget *dropdown = gtk_drop_down_new_from_strings(copy);
    g_free(copy);
    return dropdown;
}

int cadex_dropdown_selected(void *dropdown) {
    guint selected = gtk_drop_down_get_selected(GTK_DROP_DOWN(dropdown));
    if (selected == GTK_INVALID_LIST_POSITION) return -1;
    return (int)selected;
}

void cadex_dropdown_set_selected(void *dropdown, int index) {
    gtk_drop_down_set_selected(GTK_DROP_DOWN(dropdown), index < 0 ? GTK_INVALID_LIST_POSITION : (guint)index);
}

static void on_dropdown_changed(GObject *object, GParamSpec *pspec, gpointer user) {
    (void)object;
    (void)pspec;
    CadexSimple *simple = user;
    simple->fn(simple->user);
}

void cadex_dropdown_on_changed(void *dropdown, void (*fn)(void *user), void *user) {
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    g_signal_connect_data(dropdown, "notify::selected", G_CALLBACK(on_dropdown_changed), simple, NULL, 0);
}

void *cadex_spin_new(double min, double max, double step) {
    return gtk_spin_button_new_with_range(min, max, step);
}

int cadex_spin_value(void *spin) {
    return gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(spin));
}

void cadex_spin_set_value(void *spin, int value) {
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(spin), (double)value);
}

static void on_spin_changed(GtkSpinButton *spin, gpointer user) {
    (void)spin;
    CadexSimple *simple = user;
    simple->fn(simple->user);
}

void cadex_spin_on_changed(void *spin, void (*fn)(void *user), void *user) {
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    g_signal_connect_data(spin, "value-changed", G_CALLBACK(on_spin_changed), simple, NULL, 0);
}

void *cadex_switch_new(int active) {
    GtkWidget *sw = gtk_switch_new();
    gtk_switch_set_active(GTK_SWITCH(sw), active ? TRUE : FALSE);
    return sw;
}

int cadex_switch_active(void *sw) {
    return gtk_switch_get_active(GTK_SWITCH(sw)) ? 1 : 0;
}

void cadex_switch_set_active(void *sw, int active) {
    gtk_switch_set_active(GTK_SWITCH(sw), active ? TRUE : FALSE);
}

static void on_switch_changed(GObject *object, GParamSpec *pspec, gpointer user) {
    (void)object;
    (void)pspec;
    CadexSimple *simple = user;
    simple->fn(simple->user);
}

void cadex_switch_on_changed(void *sw, void (*fn)(void *user), void *user) {
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    g_signal_connect_data(sw, "notify::active", G_CALLBACK(on_switch_changed), simple, NULL, 0);
}

void *cadex_window_new_dialog(void *parent, const char *title, int width, int height) {
    GtkWidget *window = gtk_window_new();
    gtk_window_set_title(GTK_WINDOW(window), title);
    gtk_window_set_default_size(GTK_WINDOW(window), width, height);
    if (parent) {
        gtk_window_set_transient_for(GTK_WINDOW(window), GTK_WINDOW(parent));
        gtk_window_set_destroy_with_parent(GTK_WINDOW(window), TRUE);
        gtk_window_set_modal(GTK_WINDOW(window), TRUE);
    }
    return window;
}

void cadex_window_hide_on_close(void *window) {
    gtk_window_set_hide_on_close(GTK_WINDOW(window), TRUE);
}

void cadex_window_hide(void *window) {
    gtk_widget_set_visible(GTK_WIDGET(window), FALSE);
}

void cadex_widget_set_margins(void *widget, int start, int end, int top, int bottom) {
    gtk_widget_set_margin_start(GTK_WIDGET(widget), start);
    gtk_widget_set_margin_end(GTK_WIDGET(widget), end);
    gtk_widget_set_margin_top(GTK_WIDGET(widget), top);
    gtk_widget_set_margin_bottom(GTK_WIDGET(widget), bottom);
}

void cadex_widget_set_size(void *widget, int width, int height) {
    gtk_widget_set_size_request(GTK_WIDGET(widget), width, height);
}

void cadex_widget_add_class(void *widget, const char *name) {
    gtk_widget_add_css_class(GTK_WIDGET(widget), name);
}

static GtkCssProvider *cadex_css = NULL;

void cadex_css_apply(const char *css) {
    GdkDisplay *display = gdk_display_get_default();
    if (!display) return;
    if (cadex_css) {
        gtk_style_context_remove_provider_for_display(display, GTK_STYLE_PROVIDER(cadex_css));
        g_object_unref(cadex_css);
    }
    cadex_css = gtk_css_provider_new();
    gtk_css_provider_load_from_string(cadex_css, css);
    gtk_style_context_add_provider_for_display(display, GTK_STYLE_PROVIDER(cadex_css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
}

void cadex_set_dark(int dark) {
    GtkSettings *settings = gtk_settings_get_default();
    if (settings) g_object_set(settings, "gtk-application-prefer-dark-theme", dark ? TRUE : FALSE, NULL);
}

void cadex_widget_unparent(void *widget) {
    gtk_widget_unparent(GTK_WIDGET(widget));
}

void cadex_widget_ref(void *widget) {
    g_object_ref(widget);
}

void cadex_widget_unref(void *widget) {
    g_object_unref(widget);
}

void cadex_widget_on_escape(void *widget, void (*fn)(void *), void *user) {
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    GtkEventController *keys = gtk_event_controller_key_new();
    g_signal_connect_data(keys, "key-pressed", G_CALLBACK(on_entry_key), simple, NULL, 0);
    gtk_widget_add_controller(GTK_WIDGET(widget), keys);
}

char *cadex_read_file(const char *path, size_t *len) {
    char *data = NULL;
    gsize size = 0;
    if (!g_file_get_contents(path, &data, &size, NULL)) return NULL;
    if (len) *len = (size_t)size;
    return data;
}

int cadex_write_file(const char *path, const char *data, size_t len) {
    return g_file_set_contents(path, data, (gssize)len, NULL) ? 1 : 0;
}

int cadex_make_dir(const char *path) {
    return g_mkdir_with_parents(path, 0755) == 0 ? 1 : 0;
}

void cadex_gtk_free(void *ptr) {
    g_free(ptr);
}

/* ---- Documents and panels (Run 4) ------------------------------------- */

void *cadex_text_view_new(void) {
    GtkWidget *view = gtk_text_view_new();
    gtk_text_view_set_monospace(GTK_TEXT_VIEW(view), TRUE);
    gtk_text_view_set_left_margin(GTK_TEXT_VIEW(view), 8);
    gtk_text_view_set_right_margin(GTK_TEXT_VIEW(view), 8);
    gtk_text_view_set_top_margin(GTK_TEXT_VIEW(view), 8);
    gtk_text_view_set_bottom_margin(GTK_TEXT_VIEW(view), 8);
    gtk_widget_set_vexpand(view, TRUE);
    gtk_widget_set_hexpand(view, TRUE);
    return view;
}

void *cadex_text_view_buffer(void *view) {
    return gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
}

void cadex_text_view_set_editable(void *view, int editable) {
    gtk_text_view_set_editable(GTK_TEXT_VIEW(view), editable ? TRUE : FALSE);
}

void cadex_text_view_set_wrap(void *view, int wrap) {
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), wrap ? GTK_WRAP_WORD_CHAR : GTK_WRAP_NONE);
}

void cadex_text_view_set_text(void *view, const char *text, size_t len) {
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
    gtk_text_buffer_set_text(buffer, text ? text : "", (int)len);
}

char *cadex_text_view_get_text(void *view, size_t *len) {
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
    GtkTextIter start, end;
    gtk_text_buffer_get_bounds(buffer, &start, &end);
    char *text = gtk_text_buffer_get_text(buffer, &start, &end, FALSE);
    if (len) *len = text ? strlen(text) : 0;
    return text;
}

static void on_text_changed(GtkTextBuffer *buffer, gpointer user) {
    (void)buffer;
    CadexSimple *simple = user;
    simple->fn(simple->user);
}

void cadex_text_view_on_changed(void *view, cadex_simple_fn fn, void *user) {
    CadexSimple *simple = g_new0(CadexSimple, 1);
    simple->fn = fn;
    simple->user = user;
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
    g_signal_connect_data(buffer, "changed", G_CALLBACK(on_text_changed), simple, NULL, 0);
}

void cadex_text_view_scroll_to_line(void *view, int line) {
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
    GtkTextIter iter;
    gtk_text_buffer_get_iter_at_line(buffer, &iter, line < 0 ? 0 : line);
    gtk_text_buffer_place_cursor(buffer, &iter);
    GtkTextMark *mark = gtk_text_buffer_create_mark(buffer, NULL, &iter, FALSE);
    gtk_text_view_scroll_to_mark(GTK_TEXT_VIEW(view), mark, 0.1, TRUE, 0.0, 0.0);
    gtk_widget_grab_focus(GTK_WIDGET(view));
}

int cadex_text_view_cursor_line(void *view) {
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
    GtkTextIter iter;
    gtk_text_buffer_get_iter_at_mark(buffer, &iter, gtk_text_buffer_get_insert(buffer));
    return gtk_text_iter_get_line(&iter);
}

void cadex_text_view_select_all(void *view) {
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(view));
    GtkTextIter start, end;
    gtk_text_buffer_get_bounds(buffer, &start, &end);
    gtk_text_buffer_select_range(buffer, &start, &end);
}

void cadex_text_view_copy(void *view) {
    gtk_widget_activate_action(GTK_WIDGET(view), "clipboard.copy", NULL);
}

void cadex_text_view_paste(void *view) {
    gtk_widget_activate_action(GTK_WIDGET(view), "clipboard.paste", NULL);
}

void cadex_text_view_cut(void *view) {
    gtk_widget_activate_action(GTK_WIDGET(view), "clipboard.cut", NULL);
}

void cadex_text_view_undo(void *view) {
    gtk_widget_activate_action(GTK_WIDGET(view), "text.undo", NULL);
}

void cadex_text_view_redo(void *view) {
    gtk_widget_activate_action(GTK_WIDGET(view), "text.redo", NULL);
}

void cadex_window_minimize(void *window) {
    if (window) gtk_window_minimize(GTK_WINDOW(window));
}

void cadex_text_buffer_add_tag(void *buffer, const char *name, unsigned rgb, int bold, int italic, int underline) {
    char color[16];
    g_snprintf(color, sizeof(color), "#%06x", rgb & 0xffffffu);
    gtk_text_buffer_create_tag(GTK_TEXT_BUFFER(buffer), name,
        "foreground", color,
        "weight", bold ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL,
        "style", italic ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL,
        "underline", underline ? PANGO_UNDERLINE_SINGLE : PANGO_UNDERLINE_NONE,
        NULL);
}

void cadex_text_buffer_apply_tag(void *buffer, const char *name, int start, int end) {
    GtkTextBuffer *buf = GTK_TEXT_BUFFER(buffer);
    GtkTextTag *tag = gtk_text_tag_table_lookup(gtk_text_buffer_get_tag_table(buf), name);
    if (!tag || end <= start) return;
    GtkTextIter a, b;
    gtk_text_buffer_get_iter_at_offset(buf, &a, start);
    gtk_text_buffer_get_iter_at_offset(buf, &b, end);
    gtk_text_buffer_apply_tag(buf, tag, &a, &b);
}

void cadex_text_buffer_remove_all_tags(void *buffer) {
    GtkTextBuffer *buf = GTK_TEXT_BUFFER(buffer);
    GtkTextIter start, end;
    gtk_text_buffer_get_bounds(buf, &start, &end);
    gtk_text_buffer_remove_all_tags(buf, &start, &end);
}

void cadex_label_set_markup_safe(void *label, const char *markup) {
    PangoAttrList *attrs = NULL;
    char *text = NULL;
    GError *error = NULL;
    if (markup && pango_parse_markup(markup, -1, 0, &attrs, &text, NULL, &error) && text) {
        gtk_label_set_markup(GTK_LABEL(label), markup);
    } else {
        gtk_label_set_text(GTK_LABEL(label), markup ? markup : "");
    }
    if (attrs) pango_attr_list_unref(attrs);
    g_free(text);
    if (error) g_error_free(error);
}

void cadex_label_set_wrap(void *label, int wrap) {
    gtk_label_set_wrap(GTK_LABEL(label), wrap ? TRUE : FALSE);
    gtk_label_set_wrap_mode(GTK_LABEL(label), PANGO_WRAP_WORD_CHAR);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0f);
    gtk_label_set_yalign(GTK_LABEL(label), 0.0f);
}

void cadex_label_set_selectable(void *label, int selectable) {
    gtk_label_set_selectable(GTK_LABEL(label), selectable ? TRUE : FALSE);
}

void cadex_entry_set_text(void *entry, const char *text) {
    gtk_editable_set_text(GTK_EDITABLE(entry), text ? text : "");
}

void cadex_entry_set_placeholder(void *entry, const char *text) {
    gtk_entry_set_placeholder_text(GTK_ENTRY(entry), text);
}

void cadex_widget_set_valign(void *widget, int align) {
    gtk_widget_set_valign(GTK_WIDGET(widget), (GtkAlign)align);
}

void cadex_widget_set_halign(void *widget, int align) {
    gtk_widget_set_halign(GTK_WIDGET(widget), (GtkAlign)align);
}

void cadex_widget_set_sensitive(void *widget, int sensitive) {
    gtk_widget_set_sensitive(GTK_WIDGET(widget), sensitive ? TRUE : FALSE);
}

typedef struct {
    cadex_key_fn fn;
    void *user;
} CadexWindowKey;

static gboolean on_window_key(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer user) {
    (void)controller;
    CadexWindowKey *key = user;
    return key->fn(keyval, keycode, (unsigned)state, key->user) ? TRUE : FALSE;
}

void cadex_window_on_key(void *window, cadex_key_fn fn, void *user) {
    CadexWindowKey *key = g_new0(CadexWindowKey, 1);
    key->fn = fn;
    key->user = user;
    GtkEventController *controller = gtk_event_controller_key_new();
    gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE);
    g_signal_connect_data(controller, "key-pressed", G_CALLBACK(on_window_key), key, NULL, 0);
    gtk_widget_add_controller(GTK_WIDGET(window), controller);
}

static void collect_tag(GtkTextTag *tag, gpointer data) {
    g_ptr_array_add(data, tag);
}

void cadex_text_buffer_clear_tags(void *buffer) {
    GtkTextBuffer *buf = GTK_TEXT_BUFFER(buffer);
    GtkTextTagTable *table = gtk_text_buffer_get_tag_table(buf);
    GPtrArray *tags = g_ptr_array_new();
    gtk_text_tag_table_foreach(table, collect_tag, tags);
    for (guint i = 0; i < tags->len; i++) {
        gtk_text_tag_table_remove(table, g_ptr_array_index(tags, i));
    }
    g_ptr_array_unref(tags);
}

typedef struct {
    GtkListBox *box;
    void (*fn)(int index, void *user);
    void *user;
} CadexListKeys;

static gboolean on_list_key(GtkEventControllerKey *controller, guint keyval, guint keycode, GdkModifierType state, gpointer user) {
    (void)controller;
    (void)keycode;
    (void)state;
    CadexListKeys *keys = user;
    GtkListBox *box = keys->box;
    if (keyval == GDK_KEY_Down || keyval == GDK_KEY_Up) {
        int count = 0;
        while (gtk_list_box_get_row_at_index(box, count)) count++;
        if (count == 0) return FALSE;
        GtkListBoxRow *row = gtk_list_box_get_selected_row(box);
        int index = row ? gtk_list_box_row_get_index(row) : -1;
        if (keyval == GDK_KEY_Down) index = index < 0 ? 0 : (index + 1) % count;
        else index = index < 0 ? count - 1 : (index + count - 1) % count;
        GtkListBoxRow *next = gtk_list_box_get_row_at_index(box, index);
        if (next) {
            gtk_list_box_select_row(box, next);
            gtk_widget_grab_focus(GTK_WIDGET(box));
        }
        return TRUE;
    }
    if (keyval == GDK_KEY_Return || keyval == GDK_KEY_KP_Enter || keyval == GDK_KEY_space) {
        GtkListBoxRow *row = gtk_list_box_get_selected_row(box);
        if (!row) row = gtk_list_box_get_row_at_index(box, 0);
        if (row) {
            keys->fn(gtk_list_box_row_get_index(row), keys->user);
            return TRUE;
        }
    }
    return FALSE;
}

void cadex_listbox_on_keys(void *box, void (*fn)(int index, void *user), void *user) {
    CadexListKeys *keys = g_new0(CadexListKeys, 1);
    keys->box = GTK_LIST_BOX(box);
    keys->fn = fn;
    keys->user = user;
    GtkEventController *controller = gtk_event_controller_key_new();
    gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE);
    g_signal_connect_data(controller, "key-pressed", G_CALLBACK(on_list_key), keys, NULL, 0);
    gtk_widget_add_controller(GTK_WIDGET(box), controller);
}

void cadex_listbox_focus_first(void *box) {
    GtkListBox *list = GTK_LIST_BOX(box);
    GtkListBoxRow *row = gtk_list_box_get_row_at_index(list, 0);
    if (row) gtk_list_box_select_row(list, row);
    gtk_widget_grab_focus(GTK_WIDGET(box));
}

/* ---- Previews and integrations (Run 5) -------------------------------- */

#ifdef CADEX_HAS_WEBKIT
#include <webkit/webkit.h>
#include <jsc/jsc.h>
#endif

int cadex_webkit_available(void) {
#ifdef CADEX_HAS_WEBKIT
    return 1;
#else
    return 0;
#endif
}

void *cadex_webview_new(void) {
#ifdef CADEX_HAS_WEBKIT
    GtkWidget *view = webkit_web_view_new();
    gtk_widget_set_vexpand(view, TRUE);
    gtk_widget_set_hexpand(view, TRUE);
    return view;
#else
    return NULL;
#endif
}

void cadex_webview_load_html(void *view, const char *html, const char *base_uri) {
#ifdef CADEX_HAS_WEBKIT
    if (view) webkit_web_view_load_html(WEBKIT_WEB_VIEW(view), html, base_uri);
#else
    (void)view; (void)html; (void)base_uri;
#endif
}

void cadex_webview_load_uri(void *view, const char *uri) {
#ifdef CADEX_HAS_WEBKIT
    if (view) webkit_web_view_load_uri(WEBKIT_WEB_VIEW(view), uri);
#else
    (void)view; (void)uri;
#endif
}

void cadex_webview_back(void *view) {
#ifdef CADEX_HAS_WEBKIT
    if (view) webkit_web_view_go_back(WEBKIT_WEB_VIEW(view));
#else
    (void)view;
#endif
}

void cadex_webview_forward(void *view) {
#ifdef CADEX_HAS_WEBKIT
    if (view) webkit_web_view_go_forward(WEBKIT_WEB_VIEW(view));
#else
    (void)view;
#endif
}

void cadex_webview_reload(void *view) {
#ifdef CADEX_HAS_WEBKIT
    if (view) webkit_web_view_reload(WEBKIT_WEB_VIEW(view));
#else
    (void)view;
#endif
}

void cadex_webview_load_file(void *view, const char *path) {
#ifdef CADEX_HAS_WEBKIT
    if (!view) return;
    char *uri = g_filename_to_uri(path, NULL, NULL);
    if (uri) {
        webkit_web_view_load_uri(WEBKIT_WEB_VIEW(view), uri);
        g_free(uri);
    }
#else
    (void)view; (void)path;
#endif
}

void *cadex_picture_new(const char *path) {
    GtkWidget *picture = gtk_picture_new_for_filename(path);
    gtk_picture_set_can_shrink(GTK_PICTURE(picture), TRUE);
    gtk_widget_set_vexpand(picture, TRUE);
    gtk_widget_set_hexpand(picture, TRUE);
    return picture;
}

void *cadex_video_new(const char *path) {
    GtkWidget *video = gtk_video_new();
    GtkMediaStream *media = gtk_media_file_new_for_filename(path);
    gtk_video_set_media_stream(GTK_VIDEO(video), GTK_MEDIA_STREAM(media));
    gtk_video_set_autoplay(GTK_VIDEO(video), FALSE);
    gtk_widget_set_vexpand(video, TRUE);
    gtk_widget_set_hexpand(video, TRUE);
    return video;
}

int cadex_inhibit_start(const char *reason) {
    char *argv[] = { "systemd-inhibit", "--what=idle:sleep", "--who=Cadex",
                     (char *)reason, "/usr/bin/sleep", "infinity", NULL };
    int pid = 0;
    GError *error = NULL;
    if (!g_spawn_async(NULL, argv, NULL, G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD,
                       NULL, NULL, &pid, &error)) {
        if (error) g_error_free(error);
        return 0;
    }
    return pid;
}

void cadex_inhibit_stop(int pid) {
    if (pid <= 0) return;
    kill(pid, SIGTERM);
    g_spawn_close_pid(pid);
}

void cadex_notify(const char *title, const char *body) {
    GApplication *app = g_application_get_default();
    if (!app) return;
    GNotification *notification = g_notification_new(title);
    g_notification_set_body(notification, body);
    g_application_send_notification(app, "cadex", notification);
    g_object_unref(notification);
}

char *cadex_list_dir(const char *path) {
    GDir *dir = g_dir_open(path, 0, NULL);
    if (!dir) return NULL;
    GString *out = g_string_new(NULL);
    const char *name = NULL;
    while ((name = g_dir_read_name(dir)) != NULL) {
        g_string_append(out, name);
        g_string_append_c(out, '\n');
    }
    g_dir_close(dir);
    return g_string_free(out, FALSE);
}

int cadex_trash_file(const char *path) {
    GFile *file = g_file_new_for_path(path);
    GError *error = NULL;
    gboolean ok = g_file_trash(file, NULL, &error);
    if (error) g_error_free(error);
    g_object_unref(file);
    return ok ? 1 : 0;
}

int cadex_window_is_active(void *window) {
    return window && gtk_window_is_active(GTK_WINDOW(window)) ? 1 : 0;
}

int cadex_path_info(const char *path, int *is_dir, long long *mtime, long long *size) {
    GStatBuf st;
    if (g_stat(path, &st) != 0) return 0;
    if (is_dir) *is_dir = S_ISDIR(st.st_mode) ? 1 : 0;
    if (mtime) *mtime = (long long)st.st_mtime;
    if (size) *size = (long long)st.st_size;
    return 1;
}

typedef struct {
    GtkWidget *view;
    GtkWidget *gutter;
} CadexGutter;

static void on_gutter_draw(GtkDrawingArea *area, cairo_t *cr, int width, int height, gpointer user) {
    CadexGutter *state = user;
    GtkTextView *view = GTK_TEXT_VIEW(state->view);
    GdkRectangle visible;
    gtk_text_view_get_visible_rect(view, &visible);
    PangoLayout *layout = gtk_widget_create_pango_layout(GTK_WIDGET(area), NULL);
    PangoFontDescription *desc = pango_font_description_from_string("Monospace 10");
    pango_layout_set_font_description(layout, desc);
    cairo_set_source_rgb(cr, 0.55, 0.55, 0.58);
    int y = visible.y;
    int guard = 0;
    while (y < visible.y + visible.height && guard < 2000) {
        guard++;
        GtkTextIter iter;
        int line_top = 0;
        gtk_text_view_get_line_at_y(view, &iter, y, &line_top);
        int line_number = gtk_text_iter_get_line(&iter);
        int line_y = 0;
        int line_height = 0;
        gtk_text_view_get_line_yrange(view, &iter, &line_y, &line_height);
        if (line_height <= 0) break;
        char text[16];
        g_snprintf(text, sizeof(text), "%d", line_number + 1);
        pango_layout_set_text(layout, text, -1);
        int tw = 0, th = 0;
        pango_layout_get_pixel_size(layout, &tw, &th);
        cairo_move_to(cr, width - tw - 6, line_y - visible.y + (line_height - th) / 2);
        pango_cairo_show_layout(cr, layout);
        y = line_y + line_height;
    }
    pango_font_description_free(desc);
    g_object_unref(layout);
}

static void on_gutter_scroll(GtkAdjustment *adjustment, gpointer user) {
    (void)adjustment;
    gtk_widget_queue_draw(GTK_WIDGET(user));
}

static void on_view_map(GtkWidget *view, gpointer user) {
    CadexGutter *state = user;
    GtkWidget *scrolled = gtk_widget_get_ancestor(view, GTK_TYPE_SCROLLED_WINDOW);
    if (!scrolled) return;
    GtkAdjustment *adjustment = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(scrolled));
    if (adjustment) {
        g_signal_connect_object(adjustment, "value-changed", G_CALLBACK(on_gutter_scroll), state->gutter, 0);
    }
}

static void on_gutter_buffer_changed(GtkTextBuffer *buffer, gpointer user) {
    (void)buffer;
    CadexGutter *state = user;
    gtk_widget_queue_draw(state->gutter);
}

void *cadex_text_view_with_gutter(void *view) {
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    GtkWidget *gutter = gtk_drawing_area_new();
    gtk_widget_set_size_request(gutter, 48, -1);
    gtk_widget_set_vexpand(gutter, TRUE);
    CadexGutter *state = g_new0(CadexGutter, 1);
    state->view = view;
    state->gutter = gutter;
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(gutter), on_gutter_draw, state, NULL);
    gtk_box_append(GTK_BOX(box), gutter);
    gtk_box_append(GTK_BOX(box), GTK_WIDGET(view));
    gtk_widget_set_hexpand(GTK_WIDGET(view), TRUE);
    gtk_widget_set_vexpand(GTK_WIDGET(view), TRUE);
    g_signal_connect(view, "map", G_CALLBACK(on_view_map), state);
    g_signal_connect(gtk_text_view_get_buffer(GTK_TEXT_VIEW(view)), "changed", G_CALLBACK(on_gutter_buffer_changed), state);
    g_object_set_data_full(G_OBJECT(box), "cadex-gutter-state", state, g_free);
    return box;
}

typedef struct {
    char *host;
    void (*fn)(const char *host, int ok, void *user);
    void *user;
} CadexProbe;

static void on_probe_exit(GPid pid, gint status, gpointer data) {
    CadexProbe *probe = data;
    int ok = g_spawn_check_wait_status(status, NULL) ? 1 : 0;
    probe->fn(probe->host, ok, probe->user);
    g_free(probe->host);
    g_free(probe);
    g_spawn_close_pid(pid);
}

void cadex_ssh_probe(const char *host, void (*fn)(const char *host, int ok, void *user), void *user) {
    char *argv[] = { "ssh", "-o", "ConnectTimeout=2", "-o", "BatchMode=yes",
                     "-o", "StrictHostKeyChecking=no", (char *)host, "true", NULL };
    CadexProbe *probe = g_new0(CadexProbe, 1);
    probe->host = g_strdup(host);
    probe->fn = fn;
    probe->user = user;
    GPid pid = 0;
    GError *error = NULL;
    if (!g_spawn_async(NULL, argv, NULL,
                       G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD |
                       G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_STDERR_TO_DEV_NULL,
                       NULL, NULL, &pid, &error)) {
        if (error) g_error_free(error);
        probe->fn(probe->host, 0, probe->user);
        g_free(probe->host);
        g_free(probe);
        return;
    }
    g_child_watch_add(pid, on_probe_exit, probe);
}

#ifdef CADEX_HAS_WEBKIT
typedef struct {
    void (*fn)(const char *payload, void *user);
    void *user;
} CadexPicker;

static void on_pick_message(WebKitUserContentManager *manager, JSCValue *value, gpointer user) {
    (void)manager;
    CadexPicker *picker = user;
    char *text = jsc_value_to_string(value);
    picker->fn(text ? text : "", picker->user);
    g_free(text);
}
#endif

int cadex_webview_enable_picker(void *view, void (*fn)(const char *payload, void *user), void *user) {
#ifdef CADEX_HAS_WEBKIT
    if (!view) return 0;
    WebKitUserContentManager *manager = webkit_web_view_get_user_content_manager(WEBKIT_WEB_VIEW(view));
    if (!manager) return 0;
    CadexPicker *picker = g_new0(CadexPicker, 1);
    picker->fn = fn;
    picker->user = user;
    g_signal_connect_data(manager, "script-message-received::cadexPick",
                          G_CALLBACK(on_pick_message), picker, NULL, 0);
    if (!webkit_user_content_manager_register_script_message_handler(manager, "cadexPick", NULL)) {
        g_free(picker);
        return 0;
    }
    return 1;
#else
    (void)view; (void)fn; (void)user;
    return 0;
#endif
}

void cadex_webview_set_picking(void *view, int enable) {
#ifdef CADEX_HAS_WEBKIT
    if (!view) return;
    const char *script =
        "window.__cadexPickInstalled || (function(){"
        "window.__cadexPickInstalled=true;"
        "document.addEventListener('mouseover',function(e){if(!window.__cadexPick)return;e.target.style.outline='2px solid #4fc1ff';},true);"
        "document.addEventListener('mouseout',function(e){if(!window.__cadexPick)return;e.target.style.outline='';},true);"
        "document.addEventListener('click',function(e){"
        "if(!window.__cadexPick)return;e.preventDefault();e.stopPropagation();"
        "var el=e.target;var sel=el.tagName.toLowerCase();"
        "if(el.id)sel+='#'+el.id;else if(el.className)sel+='.'+String(el.className).trim().split(/\\s+/).join('.');"
        "var data={selector:sel,tag:el.tagName,id:el.id||'',classes:String(el.className||''),text:(el.innerText||'').slice(0,200),href:el.href||'',html:(el.outerHTML||'').slice(0,2000)};"
        "window.webkit.messageHandlers.cadexPick.postMessage(JSON.stringify(data));"
        "window.__cadexPick=false;el.style.outline='';},true);})();"
        "window.__cadexPick=true;";
    if (!enable) {
        script = "window.__cadexPick=false;";
    }
    webkit_web_view_evaluate_javascript(WEBKIT_WEB_VIEW(view), script, -1, NULL, NULL, NULL, NULL, NULL);
#else
    (void)view; (void)enable;
#endif
}

void cadex_webview_test_pick(void *view) {
#ifdef CADEX_HAS_WEBKIT
    if (!view) return;
    const char *script = "window.webkit.messageHandlers.cadexPick.postMessage(JSON.stringify({selector:'test',tag:'TEST',text:'Synthetic pick'}));";
    webkit_web_view_evaluate_javascript(WEBKIT_WEB_VIEW(view), script, -1, NULL, NULL, NULL, NULL, NULL);
#else
    (void)view;
#endif
}

/* ---- StatusNotifierItem (Run 5, final backlog) ------------------------ */

static const char *sni_xml =
    "<node>"
    "<interface name='org.kde.StatusNotifierItem'>"
    "<property name='Category' type='s' access='read'/>"
    "<property name='Id' type='s' access='read'/>"
    "<property name='Title' type='s' access='read'/>"
    "<property name='Status' type='s' access='read'/>"
    "<property name='IconName' type='s' access='read'/>"
    "<property name='Menu' type='o' access='read'/>"
    "<property name='ItemIsMenu' type='b' access='read'/>"
    "<method name='Activate'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "<method name='SecondaryActivate'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "<method name='ContextMenu'><arg type='i' direction='in'/><arg type='i' direction='in'/></method>"
    "<method name='Scroll'><arg type='i' direction='in'/><arg type='s' direction='in'/></method>"
    "</interface></node>";

static const char *menu_xml =
    "<node>"
    "<interface name='com.canonical.dbusmenu'>"
    "<property name='Version' type='u' access='read'/>"
    "<property name='Status' type='s' access='read'/>"
    "<property name='TextDirection' type='s' access='read'/>"
    "<property name='IconThemePath' type='as' access='read'/>"
    "<method name='GetLayout'><arg type='i' direction='in'/><arg type='i' direction='in'/><arg type='as' direction='in'/>"
    "<arg type='u' direction='out'/><arg type='(ia{sv}av)' direction='out'/></method>"
    "<method name='GetGroupProperties'><arg type='ai' direction='in'/><arg type='as' direction='in'/>"
    "<arg type='a(ia{sv})' direction='out'/></method>"
    "<method name='GetProperty'><arg type='i' direction='in'/><arg type='s' direction='in'/>"
    "<arg type='v' direction='out'/></method>"
    "<method name='Event'><arg type='i' direction='in'/><arg type='s' direction='in'/>"
    "<arg type='v' direction='in'/><arg type='u' direction='in'/></method>"
    "<method name='EventGroup'><arg type='a(isvu)' direction='in'/><arg type='i' direction='out'/></method>"
    "<method name='AboutToShow'><arg type='i' direction='in'/><arg type='b' direction='out'/></method>"
    "<method name='AboutToShowGroup'><arg type='ai' direction='in'/><arg type='ai' direction='out'/>"
    "<arg type='ai' direction='out'/></method>"
    "</interface></node>";

static GDBusConnection *cadex_bus = NULL;
static GtkWindow *cadex_tray_window = NULL;
static void (*cadex_tray_fn)(void *user) = NULL;
static void *cadex_tray_user = NULL;
static guint cadex_sni_id = 0;
static guint cadex_menu_id = 0;

static void tray_activate(void) {
    if (cadex_tray_fn) cadex_tray_fn(cadex_tray_user);
}

static void sni_method_call(GDBusConnection *connection, const char *sender, const char *object_path,
                            const char *interface_name, const char *method_name, GVariant *parameters,
                            GDBusMethodInvocation *invocation, gpointer user_data) {
    (void)connection; (void)sender; (void)object_path; (void)interface_name; (void)parameters; (void)user_data;
    if (g_strcmp0(method_name, "Activate") == 0) tray_activate();
    else if (g_strcmp0(method_name, "SecondaryActivate") == 0) tray_activate();
    g_dbus_method_invocation_return_value(invocation, NULL);
}

static GVariant *sni_get_property(GDBusConnection *connection, const char *sender, const char *object_path,
                                  const char *interface_name, const char *property_name, GError **error,
                                  gpointer user_data) {
    (void)connection; (void)sender; (void)object_path; (void)interface_name; (void)error; (void)user_data;
    if (g_strcmp0(property_name, "Category") == 0) return g_variant_new_string("ApplicationStatus");
    if (g_strcmp0(property_name, "Id") == 0) return g_variant_new_string("cadex");
    if (g_strcmp0(property_name, "Title") == 0) return g_variant_new_string("Cadex");
    if (g_strcmp0(property_name, "Status") == 0) return g_variant_new_string("Active");
    if (g_strcmp0(property_name, "IconName") == 0) return g_variant_new_string("cadex");
    if (g_strcmp0(property_name, "Menu") == 0) return g_variant_new_object_path("/StatusNotifierItem/Menu");
    if (g_strcmp0(property_name, "ItemIsMenu") == 0) return g_variant_new_boolean(FALSE);
    return NULL;
}

static void menu_method_call(GDBusConnection *connection, const char *sender, const char *object_path,
                             const char *interface_name, const char *method_name, GVariant *parameters,
                             GDBusMethodInvocation *invocation, gpointer user_data) {
    (void)connection; (void)sender; (void)object_path; (void)interface_name; (void)parameters; (void)user_data;
    if (g_strcmp0(method_name, "GetLayout") == 0) {
        GVariantBuilder layout;
        g_variant_builder_init(&layout, G_VARIANT_TYPE("(ia{sv}av)"));
        g_variant_builder_add(&layout, "i", 0);
        g_variant_builder_open(&layout, G_VARIANT_TYPE("a{sv}"));
        g_variant_builder_close(&layout);
        g_variant_builder_open(&layout, G_VARIANT_TYPE("av"));
        g_variant_builder_close(&layout);
        g_dbus_method_invocation_return_value(invocation,
            g_variant_new("(u@(ia{sv}av))", 1, g_variant_builder_end(&layout)));
        return;
    }
    if (g_strcmp0(method_name, "GetGroupProperties") == 0) {
        GVariantBuilder empty;
        g_variant_builder_init(&empty, G_VARIANT_TYPE("a(ia{sv})"));
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(@a(ia{sv}))", g_variant_builder_end(&empty)));
        return;
    }
    if (g_strcmp0(method_name, "GetProperty") == 0) {
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(v)", g_variant_new_string("")));
        return;
    }
    if (g_strcmp0(method_name, "AboutToShow") == 0) {
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(b)", FALSE));
        return;
    }
    if (g_strcmp0(method_name, "AboutToShowGroup") == 0) {
        GVariantBuilder empty;
        g_variant_builder_init(&empty, G_VARIANT_TYPE("ai"));
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(@ai@ai)", g_variant_builder_end(&empty), g_variant_builder_end(&empty)));
        return;
    }
    if (g_strcmp0(method_name, "EventGroup") == 0) {
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(i)", 0));
        return;
    }
    g_dbus_method_invocation_return_value(invocation, NULL);
}

static GVariant *menu_get_property(GDBusConnection *connection, const char *sender, const char *object_path,
                                   const char *interface_name, const char *property_name, GError **error,
                                   gpointer user_data) {
    (void)connection; (void)sender; (void)object_path; (void)interface_name; (void)error; (void)user_data;
    if (g_strcmp0(property_name, "Version") == 0) return g_variant_new_uint32(3);
    if (g_strcmp0(property_name, "Status") == 0) return g_variant_new_string("normal");
    if (g_strcmp0(property_name, "TextDirection") == 0) return g_variant_new_string("ltr");
    if (g_strcmp0(property_name, "IconThemePath") == 0) {
        GVariantBuilder paths;
        g_variant_builder_init(&paths, G_VARIANT_TYPE("as"));
        return g_variant_builder_end(&paths);
    }
    return NULL;
}

static const GDBusInterfaceVTable sni_vtable = { sni_method_call, sni_get_property, NULL, {0} };
static const GDBusInterfaceVTable menu_vtable = { menu_method_call, menu_get_property, NULL, {0} };

void cadex_tray_start(void *window, void (*fn)(void *user), void *user) {
    if (cadex_bus) return;
    cadex_tray_window = GTK_WINDOW(window);
    cadex_tray_fn = fn;
    cadex_tray_user = user;
    GError *error = NULL;
    cadex_bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!cadex_bus) {
        if (error) g_error_free(error);
        return;
    }
    GDBusNodeInfo *sni = g_dbus_node_info_new_for_xml(sni_xml, NULL);
    GDBusNodeInfo *menu = g_dbus_node_info_new_for_xml(menu_xml, NULL);
    if (sni) cadex_sni_id = g_dbus_connection_register_object(cadex_bus, "/StatusNotifierItem", sni->interfaces[0], &sni_vtable, NULL, NULL, NULL);
    if (menu) cadex_menu_id = g_dbus_connection_register_object(cadex_bus, "/StatusNotifierItem/Menu", menu->interfaces[0], &menu_vtable, NULL, NULL, NULL);
    g_dbus_connection_call(cadex_bus, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                           "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem",
                           g_variant_new("(s)", "/StatusNotifierItem"), NULL, G_DBUS_CALL_FLAGS_NONE,
                           -1, NULL, NULL, NULL);
    if (sni) g_dbus_node_info_unref(sni);
    if (menu) g_dbus_node_info_unref(menu);
}

/* ---- Adwaita shell ---------------------------------------------------- */

void *cadex_adw_window_split_new(void) {
#ifdef CADEX_HAS_ADW
    return adw_overlay_split_view_new();
#else
    return NULL;
#endif
}

void cadex_adw_split_set_sidebar(void *split, void *sidebar) {
#ifdef CADEX_HAS_ADW
    adw_overlay_split_view_set_sidebar(ADW_OVERLAY_SPLIT_VIEW(split), GTK_WIDGET(sidebar));
#else
    (void)split; (void)sidebar;
#endif
}

void cadex_adw_split_set_content(void *split, void *content) {
#ifdef CADEX_HAS_ADW
    adw_overlay_split_view_set_content(ADW_OVERLAY_SPLIT_VIEW(split), GTK_WIDGET(content));
#else
    (void)split; (void)content;
#endif
}

void cadex_adw_split_set_show_sidebar(void *split, int show) {
#ifdef CADEX_HAS_ADW
    adw_overlay_split_view_set_show_sidebar(ADW_OVERLAY_SPLIT_VIEW(split), show ? TRUE : FALSE);
#else
    (void)split; (void)show;
#endif
}

int cadex_adw_split_get_show_sidebar(void *split) {
#ifdef CADEX_HAS_ADW
    return adw_overlay_split_view_get_show_sidebar(ADW_OVERLAY_SPLIT_VIEW(split)) ? 1 : 0;
#else
    (void)split;
    return 0;
#endif
}

void *cadex_adw_view_switcher_new(void *stack) {
#ifdef CADEX_HAS_ADW
    GtkWidget *switcher = adw_view_switcher_new();
    adw_view_switcher_set_stack(ADW_VIEW_SWITCHER(switcher), ADW_VIEW_STACK(stack));
    return switcher;
#else
    (void)stack;
    return NULL;
#endif
}

void *cadex_adw_toast_overlay_new(void) {
#ifdef CADEX_HAS_ADW
    return adw_toast_overlay_new();
#else
    return NULL;
#endif
}

void cadex_adw_toast_overlay_set_child(void *overlay, void *child) {
#ifdef CADEX_HAS_ADW
    adw_toast_overlay_set_child(ADW_TOAST_OVERLAY(overlay), GTK_WIDGET(child));
#else
    (void)overlay; (void)child;
#endif
}

void cadex_adw_toast(void *overlay, const char *text) {
#ifdef CADEX_HAS_ADW
    if (!overlay) return;
    adw_toast_overlay_add_toast(ADW_TOAST_OVERLAY(overlay), adw_toast_new(text));
#else
    (void)overlay; (void)text;
#endif
}

void *cadex_adw_window_title_new(const char *title, const char *subtitle) {
#ifdef CADEX_HAS_ADW
    return adw_window_title_new(title, subtitle);
#else
    return NULL;
#endif
}

void cadex_adw_window_title_set(void *title, const char *text, const char *subtitle) {
#ifdef CADEX_HAS_ADW
    adw_window_title_set_title(ADW_WINDOW_TITLE(title), text);
    adw_window_title_set_subtitle(ADW_WINDOW_TITLE(title), subtitle);
#else
    (void)title; (void)text; (void)subtitle;
#endif
}

void *cadex_adw_icon_button(const char *icon, void (*fn)(void *), void *user) {
    GtkWidget *button = gtk_button_new_from_icon_name(icon);
    gtk_widget_add_css_class(button, "flat");
    if (fn) {
        CadexSimple *simple = g_new0(CadexSimple, 1);
        simple->fn = fn;
        simple->user = user;
        g_signal_connect_data(button, "clicked", G_CALLBACK(on_button_clicked), simple, NULL, 0);
    }
    return button;
}

void *cadex_adw_menu_button_new(const char *icon, void *popover) {
    GtkWidget *button = gtk_menu_button_new();
    gtk_menu_button_set_icon_name(GTK_MENU_BUTTON(button), icon);
    gtk_widget_add_css_class(button, "flat");
    if (popover) gtk_menu_button_set_popover(GTK_MENU_BUTTON(button), GTK_WIDGET(popover));
    return button;
}

void *cadex_adw_popover_new(void) {
    return gtk_popover_new();
}

void cadex_adw_popover_set_child(void *popover, void *child) {
    gtk_popover_set_child(GTK_POPOVER(popover), GTK_WIDGET(child));
}

void *cadex_adw_nav_row_new(const char *icon, const char *title) {
#ifdef CADEX_HAS_ADW
    GtkWidget *row = adw_action_row_new();
    adw_preferences_row_set_title(ADW_PREFERENCES_ROW(row), title);
    GtkWidget *image = gtk_image_new_from_icon_name(icon);
    adw_action_row_add_prefix(ADW_ACTION_ROW(row), image);
    gtk_list_box_row_set_activatable(GTK_LIST_BOX_ROW(row), TRUE);
    return row;
#else
    (void)icon;
    GtkWidget *row = gtk_list_box_row_new();
    GtkWidget *label = gtk_label_new(title);
    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), label);
    return row;
#endif
}

void *cadex_adw_action_row_new(const char *title, const char *subtitle) {
#ifdef CADEX_HAS_ADW
    GtkWidget *row = adw_action_row_new();
    adw_preferences_row_set_title(ADW_PREFERENCES_ROW(row), title);
    if (subtitle) adw_action_row_set_subtitle(ADW_ACTION_ROW(row), subtitle);
    return row;
#else
    (void)subtitle;
    return gtk_list_box_row_new();
#endif
}

void cadex_adw_action_row_add_prefix(void *row, void *widget) {
#ifdef CADEX_HAS_ADW
    adw_action_row_add_prefix(ADW_ACTION_ROW(row), GTK_WIDGET(widget));
#else
    (void)row; (void)widget;
#endif
}

void cadex_adw_action_row_add_suffix(void *row, void *widget) {
#ifdef CADEX_HAS_ADW
    adw_action_row_add_suffix(ADW_ACTION_ROW(row), GTK_WIDGET(widget));
#else
    (void)row; (void)widget;
#endif
}

void *cadex_adw_preferences_window_new(void *parent, const char *title) {
#ifdef CADEX_HAS_ADW
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    GtkWidget *window = adw_preferences_window_new();
    G_GNUC_END_IGNORE_DEPRECATIONS
    gtk_window_set_title(GTK_WINDOW(window), title);
    if (parent) gtk_window_set_transient_for(GTK_WINDOW(window), GTK_WINDOW(parent));
    gtk_window_set_default_size(GTK_WINDOW(window), 640, 560);
    return window;
#else
    (void)parent; (void)title;
    return NULL;
#endif
}

void *cadex_adw_preferences_page_new(void) {
#ifdef CADEX_HAS_ADW
    return adw_preferences_page_new();
#else
    return NULL;
#endif
}

void *cadex_adw_preferences_group_new(const char *title) {
#ifdef CADEX_HAS_ADW
    GtkWidget *group = adw_preferences_group_new();
    adw_preferences_group_set_title(ADW_PREFERENCES_GROUP(group), title);
    return group;
#else
    (void)title;
    return NULL;
#endif
}

void cadex_adw_preferences_group_add(void *group, void *row) {
#ifdef CADEX_HAS_ADW
    adw_preferences_group_add(ADW_PREFERENCES_GROUP(group), GTK_WIDGET(row));
#else
    (void)group; (void)row;
#endif
}

void cadex_adw_preferences_page_add(void *page, void *group) {
#ifdef CADEX_HAS_ADW
    adw_preferences_page_add(ADW_PREFERENCES_PAGE(page), ADW_PREFERENCES_GROUP(group));
#else
    (void)page; (void)group;
#endif
}

void cadex_adw_preferences_window_add(void *window, void *page) {
#ifdef CADEX_HAS_ADW
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    adw_preferences_window_add(ADW_PREFERENCES_WINDOW(window), ADW_PREFERENCES_PAGE(page));
    G_GNUC_END_IGNORE_DEPRECATIONS
#else
    (void)window; (void)page;
#endif
}

void *cadex_adw_status_page_new(const char *icon, const char *title, const char *description) {
#ifdef CADEX_HAS_ADW
    GtkWidget *page = adw_status_page_new();
    adw_status_page_set_icon_name(ADW_STATUS_PAGE(page), icon);
    adw_status_page_set_title(ADW_STATUS_PAGE(page), title);
    adw_status_page_set_description(ADW_STATUS_PAGE(page), description);
    return page;
#else
    (void)icon; (void)title; (void)description;
    return NULL;
#endif
}

void *cadex_adw_clamp_new(int max_width) {
#ifdef CADEX_HAS_ADW
    GtkWidget *clamp = adw_clamp_new();
    adw_clamp_set_maximum_size(ADW_CLAMP(clamp), max_width);
    return clamp;
#else
    (void)max_width;
    return NULL;
#endif
}

void cadex_widget_set_tooltip(void *widget, const char *text) {
    gtk_widget_set_tooltip_text(GTK_WIDGET(widget), text);
}

void cadex_widget_set_flat(void *widget) {
    gtk_widget_add_css_class(GTK_WIDGET(widget), "flat");
}

void cadex_listbox_append_widget(void *box, void *widget) {
    gtk_list_box_append(GTK_LIST_BOX(box), GTK_WIDGET(widget));
}

void cadex_listbox_append_action(void *box, const char *icon, const char *title, const char *subtitle) {
#ifdef CADEX_HAS_ADW
    GtkWidget *row = adw_action_row_new();
    adw_preferences_row_set_title(ADW_PREFERENCES_ROW(row), title);
    if (subtitle && subtitle[0]) adw_action_row_set_subtitle(ADW_ACTION_ROW(row), subtitle);
    if (icon && icon[0]) adw_action_row_add_prefix(ADW_ACTION_ROW(row), gtk_image_new_from_icon_name(icon));
    gtk_list_box_append(GTK_LIST_BOX(box), row);
#else
    (void)icon; (void)subtitle;
    gtk_list_box_append(GTK_LIST_BOX(box), gtk_label_new(title));
#endif
}

void cadex_listbox_select(void *box, int index) {
    GtkListBoxRow *row = gtk_list_box_get_row_at_index(GTK_LIST_BOX(box), index);
    if (row) gtk_list_box_select_row(GTK_LIST_BOX(box), row);
}
