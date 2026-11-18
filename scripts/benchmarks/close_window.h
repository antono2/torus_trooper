#ifndef TT_BENCHMARK_CLOSE_WINDOW_H
#define TT_BENCHMARK_CLOSE_WINDOW_H

#include <X11/Xlib.h>

// Deliver the same close request as a window manager, even under bare Xvfb.
static int tt_benchmark_close_window(unsigned long window) {
    Display *display = XOpenDisplay(NULL);
    if (!display)
        return 0;
    XEvent event = {0};
    event.xclient.type = ClientMessage;
    event.xclient.window = window;
    event.xclient.message_type = XInternAtom(display, "WM_PROTOCOLS", False);
    event.xclient.format = 32;
    event.xclient.data.l[0] = XInternAtom(display, "WM_DELETE_WINDOW", False);
    event.xclient.data.l[1] = CurrentTime;
    int sent = XSendEvent(display, window, False, NoEventMask, &event);
    XCloseDisplay(display);
    return sent;
}

#endif
