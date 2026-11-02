#ifndef CADEX_GTK_SHIM_H
#define CADEX_GTK_SHIM_H

#include <stddef.h>

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
void cadex_widget_expand_h(void *widget);
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

/* ---- Shell widgets (Run 3) -------------------------------------------- */

void *cadex_box_new_h(int spacing);
void *cadex_notebook_new(void);
void cadex_notebook_append(void *notebook, void *page, void *label);
void cadex_notebook_insert(void *notebook, int index, void *page, void *label);
void cadex_notebook_remove(void *notebook, int index);
int cadex_notebook_page_num(void *notebook, void *page);
int cadex_notebook_current(void *notebook);
void cadex_notebook_set_current(void *notebook, int index);
int cadex_notebook_count(void *notebook);
void *cadex_notebook_page(void *notebook, int index);
void cadex_notebook_on_switch(void *notebook, void (*fn)(void *notebook, int index, void *user), void *user);

void *cadex_paned_new(int orientation);
void cadex_paned_set_start(void *paned, void *child);
void cadex_paned_set_end(void *paned, void *child);
void cadex_paned_set_position(void *paned, int position);

void *cadex_stack_new(void);
void cadex_stack_add(void *stack, void *child, const char *name);
void cadex_stack_set(void *stack, const char *name);

void *cadex_label_new(const char *text);
void cadex_label_set(void *label, const char *text);
void cadex_label_ellipsize(void *label);
void cadex_label_set_xalign(void *label, double align);
void *cadex_button_new(const char *text, void (*fn)(void *), void *user);
void *cadex_header_button_start(void *header, const char *text, cadex_simple_fn fn, void *user);
void cadex_header_widget_start(void *header, void *widget);
void cadex_header_widget_end(void *header, void *widget);
void cadex_button_set_text(void *button, const char *text);
void cadex_button_set_icon(void *button, const char *icon);
void cadex_text_set_font(const char *font);
void cadex_widget_unparent(void *widget);
void cadex_widget_ref(void *widget);
void cadex_widget_unref(void *widget);
void cadex_widget_on_escape(void *widget, void (*fn)(void *), void *user);
char *cadex_read_file(const char *path, size_t *len);
int cadex_write_file(const char *path, const char *data, size_t len);
int cadex_make_dir(const char *path);
void cadex_gtk_free(void *ptr);

void *cadex_listbox_new(void);
void cadex_listbox_clear(void *box);
void cadex_listbox_append(void *box, const char *text);
void cadex_listbox_on_activated(void *box, void (*fn)(int index, void *user), void *user);
void cadex_listbox_on_keys(void *box, void (*fn)(int index, void *user), void *user);
void cadex_listbox_focus_first(void *box);
void *cadex_scrolled_new(void *child);

void *cadex_dropdown_new(const char *const *items, int count);
int cadex_dropdown_selected(void *dropdown);
void cadex_dropdown_set_selected(void *dropdown, int index);
void cadex_dropdown_on_changed(void *dropdown, void (*fn)(void *user), void *user);
void *cadex_spin_new(double min, double max, double step);
int cadex_spin_value(void *spin);
void cadex_spin_set_value(void *spin, int value);
void cadex_spin_on_changed(void *spin, void (*fn)(void *user), void *user);
void *cadex_switch_new(int active);
int cadex_switch_active(void *sw);
void cadex_switch_set_active(void *sw, int active);
void cadex_switch_on_changed(void *sw, void (*fn)(void *user), void *user);

void *cadex_window_new_dialog(void *parent, const char *title, int width, int height);
void cadex_window_hide_on_close(void *window);
void cadex_window_hide(void *window);
void cadex_widget_set_size(void *widget, int width, int height);
void cadex_widget_set_margins(void *widget, int start, int end, int top, int bottom);
void *cadex_image_new(const char *icon);
void cadex_widget_clip(void *widget);
void cadex_widget_add_class(void *widget, const char *name);
void cadex_css_apply(const char *css);
void cadex_set_dark(int dark);

/* ---- Documents and panels (Run 4) ------------------------------------- */

void *cadex_text_view_new(void);
void *cadex_text_view_with_gutter(void *view);
void *cadex_text_view_buffer(void *view);
void cadex_text_view_set_editable(void *view, int editable);
void cadex_text_view_set_wrap(void *view, int wrap);
void cadex_text_view_set_text(void *view, const char *text, size_t len);
char *cadex_text_view_get_text(void *view, size_t *len);
void cadex_text_view_on_changed(void *view, cadex_simple_fn fn, void *user);
void cadex_text_view_scroll_to_line(void *view, int line);
int cadex_text_view_cursor_line(void *view);
void cadex_text_view_select_all(void *view);
void cadex_text_view_copy(void *view);
void cadex_text_view_paste(void *view);
void cadex_text_view_cut(void *view);
void cadex_text_view_undo(void *view);
void cadex_text_view_redo(void *view);
void cadex_window_minimize(void *window);

void cadex_text_buffer_add_tag(void *buffer, const char *name, unsigned rgb, int bold, int italic, int underline);
void cadex_text_buffer_apply_tag(void *buffer, const char *name, int start, int end);
void cadex_text_buffer_remove_all_tags(void *buffer);
void cadex_text_buffer_clear_tags(void *buffer);

void cadex_label_set_markup_safe(void *label, const char *markup);
void cadex_label_set_wrap(void *label, int wrap);
void cadex_label_set_selectable(void *label, int selectable);
void cadex_entry_set_text(void *entry, const char *text);
void cadex_entry_set_placeholder(void *entry, const char *text);
void cadex_widget_set_valign(void *widget, int align);
void cadex_widget_set_halign(void *widget, int align);
void cadex_widget_set_sensitive(void *widget, int sensitive);
void cadex_window_on_key(void *window, cadex_key_fn fn, void *user);

/* ---- Previews and integrations (Run 5) -------------------------------- */

int cadex_webkit_available(void);
void *cadex_webview_new(void);
void cadex_webview_load_html(void *view, const char *html, const char *base_uri);
void cadex_webview_load_uri(void *view, const char *uri);
void cadex_webview_load_file(void *view, const char *path);
int cadex_webview_enable_picker(void *view, void (*fn)(const char *payload, void *user), void *user);
void cadex_webview_set_picking(void *view, int enable);
void cadex_webview_test_pick(void *view);
void cadex_webview_back(void *view);
void cadex_webview_forward(void *view);
void cadex_webview_reload(void *view);
void *cadex_picture_new(const char *path);
void *cadex_video_new(const char *path);
int cadex_inhibit_start(const char *reason);
void cadex_inhibit_stop(int pid);
void cadex_notify(const char *title, const char *body);
char *cadex_list_dir(const char *path);
int cadex_path_info(const char *path, int *is_dir, long long *mtime, long long *size);
int cadex_trash_file(const char *path);
void cadex_ssh_probe(const char *host, void (*fn)(const char *host, int ok, void *user), void *user);
void cadex_tray_start(void *window, void (*fn)(void *user), void *user);
int cadex_window_is_active(void *window);

/* ---- Adwaita shell (UI rewrite) --------------------------------------- */

void cadex_window_set_bottom_bar(void *window, void *widget);
void *cadex_adw_tab_bar_new(void);
void cadex_tab_bar_set_notebook(void *bar, void *notebook);
void cadex_header_set_title_widget(void *header, void *widget);
void *cadex_adw_window_split_new(void);
void cadex_adw_split_set_sidebar_width(void *split, int width);
void cadex_adw_split_set_sidebar(void *split, void *sidebar);
void cadex_adw_split_set_content(void *split, void *content);
void cadex_adw_split_set_show_sidebar(void *split, int show);
int cadex_adw_split_get_show_sidebar(void *split);
void *cadex_adw_view_switcher_new(void *stack);
void *cadex_adw_toast_overlay_new(void);
void cadex_adw_toast_overlay_set_child(void *overlay, void *child);
void cadex_adw_toast(void *overlay, const char *text);
void *cadex_adw_window_title_new(const char *title, const char *subtitle);
void cadex_adw_window_title_set(void *title, const char *text, const char *subtitle);
void *cadex_adw_icon_button(const char *icon, void (*fn)(void *), void *user);
void *cadex_adw_menu_button_new(const char *icon, void *popover);
void *cadex_adw_popover_new(void);
void cadex_adw_popover_set_child(void *popover, void *child);
void *cadex_adw_nav_row_new(const char *icon, const char *title);
void *cadex_adw_action_row_new(const char *title, const char *subtitle);
void cadex_adw_action_row_add_prefix(void *row, void *widget);
void cadex_adw_action_row_add_suffix(void *row, void *widget);
void *cadex_adw_preferences_window_new(void *parent, const char *title);
void *cadex_adw_preferences_page_new(void);
void *cadex_adw_preferences_group_new(const char *title);
void cadex_adw_preferences_group_add(void *group, void *row);
void cadex_adw_preferences_page_add(void *page, void *group);
void cadex_adw_preferences_window_add(void *window, void *page);
void *cadex_adw_status_page_new(const char *icon, const char *title, const char *description);
void *cadex_adw_clamp_new(int max_width);
void cadex_widget_set_tooltip(void *widget, const char *text);
void cadex_widget_set_flat(void *widget);
void cadex_listbox_append_widget(void *box, void *widget);
void cadex_listbox_append_action(void *box, const char *icon, const char *title, const char *subtitle);
void cadex_listbox_select(void *box, int index);
void cadex_notebook_set_title(void *notebook, void *child, const char *title);
void cadex_notebook_size(void *notebook, int *w, int *h);
void cadex_notebook_on_close(void *notebook, void (*fn)(void *child, void *user), void *user);
void cadex_stack_on_changed(void *stack, void (*fn)(const char *name, void *user), void *user);

#endif
