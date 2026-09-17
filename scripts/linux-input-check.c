/* Synthetic input only, on the private display created by linux-input-check.sh.
 * Compare GTK, plain WebKit and Linger's real composer without accounts/audio. */
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include <stdio.h>
#include <string.h>

static GtkWidget *field;
static const char *surface;
static const char *mode;
static const char *sample;
static gboolean web;
static int outcome = 1;

static void report(const char *text) {
    outcome = !strcmp(text, sample) ? 0 : 2;
    printf("%s %s %s: %s\n", g_getenv("GDK_BACKEND"), surface, mode,
           outcome == 0 ? "MATCH" : "DIFFERENT");
    gtk_main_quit();
}

static void result(GObject *source, GAsyncResult *res, gpointer unused) {
    (void)unused;
    GError *error = NULL;
    JSCValue *value = webkit_web_view_evaluate_javascript_finish(WEBKIT_WEB_VIEW(source), res, &error);
    if (value && jsc_value_is_string(value)) {
        char *text = jsc_value_to_string(value);
        report(text);
        g_free(text);
    } else {
        fputs("Could not read the fixture draft, or it unexpectedly submitted.\n", stderr);
        gtk_main_quit();
    }
    g_clear_object(&value);
    g_clear_error(&error);
}

static gboolean finish(gpointer unused) {
    (void)unused;
    if (web) {
        webkit_web_view_evaluate_javascript(WEBKIT_WEB_VIEW(field),
            "document.documentElement.dataset.submitted === 'yes' ? null : document.querySelector('textarea').value",
            -1, NULL, NULL, NULL, result, NULL);
    } else report(gtk_entry_get_text(GTK_ENTRY(field)));
    return G_SOURCE_REMOVE;
}

static gboolean paste(gpointer unused) {
    (void)unused;
    /* Invoke the native paste action, as physical Ctrl+V does. Using wtype
     * for that shortcut would mix the broken keyboard path into this control. */
    if (web) webkit_web_view_execute_editing_command(WEBKIT_WEB_VIEW(field), WEBKIT_EDITING_COMMAND_PASTE);
    else g_signal_emit_by_name(field, "paste-clipboard");
    return G_SOURCE_REMOVE;
}

static gboolean type(gpointer unused) {
    (void)unused;
    GError *error = NULL;
    if (!strcmp(mode, "clipboard")) {
        char *copy[] = {"wl-copy", "--", (char *)sample, NULL};
        int status = 0;
        if (!g_spawn_sync(NULL, copy, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL, &status, &error)
            || !g_spawn_check_wait_status(status, &error)) goto failed;
        g_timeout_add(200, paste, NULL);
    } else {
        char *input[] = {"wtype", "-d", (char *)mode, (char *)sample, NULL};
        if (!g_spawn_async(NULL, input, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, &error)) goto failed;
    }
    g_timeout_add(2000, finish, NULL);
    return G_SOURCE_REMOVE;
failed:
    fputs("Could not start the synthetic input driver.\n", stderr);
    g_clear_error(&error);
    gtk_main_quit();
    return G_SOURCE_REMOVE;
}

static void loaded(WebKitWebView *view, WebKitLoadEvent event, gpointer unused) {
    (void)view; (void)unused;
    if (event == WEBKIT_LOAD_FINISHED) g_timeout_add(500, type, NULL);
}

int main(int argc, char **argv) {
    if (!g_getenv("LINGER_PRIVATE_INPUT_DISPLAY") || argc != 3) return 1;
    gtk_init(&argc, &argv);
    surface = argv[1];
    mode = argv[2];
    web = strcmp(surface, "gtk") != 0;
    sample = !strcmp(mode, "clipboard") && web
        ? "hello world! Voice 123.\nCafé — a second line 👋"
        : "hello world! Voice 123.";
    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_default_size(GTK_WINDOW(window), 600, 300);
    field = web ? webkit_web_view_new() : gtk_entry_new();
    gtk_container_add(GTK_CONTAINER(window), field);
    gtk_widget_show_all(window);
    gtk_widget_grab_focus(field);
    if (web) {
        g_signal_connect(field, "load-changed", G_CALLBACK(loaded), NULL);
        if (!strcmp(surface, "composer")) {
            webkit_web_view_load_uri(WEBKIT_WEB_VIEW(field), "http://127.0.0.1:1422/tests/fixtures/composer.html");
        } else {
            webkit_web_view_load_html(WEBKIT_WEB_VIEW(field), "<!doctype html><textarea autofocus></textarea>", "http://localhost/");
        }
    } else g_timeout_add(500, type, NULL);
    gtk_main();
    return outcome;
}
