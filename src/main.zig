const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const Backend = dvui.backend;
const App = @import("app.zig").App;
const Item = @import("app.zig").Item;

comptime {
    std.debug.assert(@hasDecl(Backend, "SDLBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");
var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();
const assert = std.debug.assert;

const vsync = true;
var scale_val: f32 = 1.0;

var g_backend: ?Backend = null;
var g_win: ?*dvui.Window = null;

var theme = @import("theme.zig").theme;
var queue_focus_text_entry = false;

pub fn main() !void {
    std.log.info("SDL version: {}", .{Backend.getSDLVersion()});

    //    dvui.Examples.show_demo_window = show_demo;

    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");

    // init SDL backend (creates and owns OS window)
    var backend = try Backend.initWindow(.{
        .allocator = gpa,
        .size = .{ .w = 450.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = vsync,
        .title = "DVUI SDL Standalone Example",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });
    g_backend = backend;
    defer backend.deinit();

    // init dvui Window (maps onto a single OS window)
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

    var app = try App.init(gpa);
    defer app.deinit();
    app.initializeFile() catch |err| {
        std.debug.print("Failed to create storage file! Err: {!}\n", .{err});
        return err;
    };

    try app.load();
    main_loop: while (app.is_running) {

        // beginWait coordinates with waitTime below to run frames only when needed
        const nstime = win.beginWait(backend.hasEvent());

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(nstime);

        // send all SDL events to dvui for processing
        const quit = try backend.addAllEvents(&win);
        if (quit) break :main_loop;

        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 253, 246, 227, 0);
        _ = Backend.c.SDL_RenderClear(backend.renderer);

        dvui.themeSet(&theme);
        process_user_input(&app);
        try gui_frame(&app);
        if (queue_focus_text_entry and !app.is_text_focused) {
            focusTextEntry(&app);
        }

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try win.end(.{});

        // cursor management
        backend.setCursor(win.cursorRequested());
        backend.textInputRect(win.textInputRequested());

        // render frame to OS
        backend.renderPresent();

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = win.waitTime(end_micros, null);
        backend.waitEventTimeout(wait_event_micros);
    }
}

//entry point of rendering
fn gui_frame(app: *App) !void {
    {
        var hbox = try dvui.box(@src(), .horizontal, .{});
        defer hbox.deinit();
        if (try dvui.button(@src(), "Save", .{}, .{ .corner_radius = dvui.Rect.all(2) })) {
            try app.save();
        }

        if (try dvui.button(@src(), "Quit", .{}, .{ .corner_radius = dvui.Rect.all(2) })) {
            try app.save();
            app.is_running = false;
            return;
        }
    }

    var vbox = try dvui.box(@src(), .vertical, .{ .gravity_x = 0.5 });
    defer vbox.deinit();

    var tl = try dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_1 });
    try tl.addText("Todo", .{});
    tl.deinit();

    renderHeader(app) catch |err| {
        std.debug.print("Failed to render header!\n", .{});
        return err;
    };
}

fn renderHeader(app: *App) !void {
    var left_alignment = dvui.Alignment.init();
    defer left_alignment.deinit();

    if (app.getFromId(app.current_selected_id).parent == null and app.insert_enabled) {
        if (try renderTextBox(app, 0)) {
            _ = try app.addNewItems(app.getText().?);
            app.clearTextEntry();
        }
    }

    var vbox = try dvui.box(@src(), .vertical, .{});
    defer vbox.deinit();

    var update = false;
    //loop over all top level items, skipping the root
    for (app.getFromId(0).children.items) |todo| {
        if (try renderTodoItem(app, app.getFromId(todo).*, 1))
            update = true;
    }

    if (update and app.text_entry != null) {
        if (app.insert_enabled)
            _ = try app.addNewItems(app.getText().?);

        if (app.edit_enabled) {
            try app.getFromId(app.current_selected_id).updateText(app.getText().?, app.allocator);
            app.edit_enabled = false;
            app.is_text_focused = false;
        }

        app.clearTextEntry();
    }
}

//render the text entry box, returns true if the user hits enter or the submit button
fn renderTextBox(app: *App, indent: f32) !bool {
    if (!app.insert_enabled and !app.edit_enabled) return false;

    var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .background = true });
    defer hbox.deinit();

    app.text_entry = try dvui.textEntry(@src(), .{
        .text = .{ .buffer = &app.text_entry_buff },
    }, .{
        .corner_radius = dvui.Rect.all(1),
        .margin = dvui.Rect{ .x = indent * App.LEFT_INDENT },
        .expand = .horizontal,
    });

    var te = app.text_entry.?;
    const enter_pressed = te.enter_pressed;
    te.deinit();

    if (app.edit_enabled and !app.text_copied) {
        //if in edit mode, copy the current selected item's text into the text entry box
        const text = app.getFromId(app.current_selected_id).text;
        te.len = app.text_entry_buff.len;
        te.text = &app.text_entry_buff;
        te.text_changed = true;
        te.textLayout.selection.cursor = text.len;

        std.mem.copyForwards(u8, &app.text_entry_buff, text);
        app.text_copied = true;
    }

    app.is_text_focused = if (dvui.focusedWidgetId()) |id| (id == te.wd.id) else false;

    const btn = try dvui.button(@src(), "Enter", .{}, .{
        .corner_radius = dvui.Rect.all(2),
        .expand = .vertical,
    });

    return (enter_pressed or btn);
}

//draw a single todo item based on its state, recursivly draws all child items as well also draws the text entry box under
//the item if its the current selected item
//returns true if text was input'd, false otherwise
fn renderTodoItem(app: *App, todo: Item, indent: f32) !bool {
    var hbox = try dvui.box(@src(), .horizontal, .{ .expand = .horizontal, .id_extra = todo.id });
    var opts = dvui.Options{ .expand = .horizontal, .id_extra = todo.id, .margin = dvui.Rect{ .x = indent * App.LEFT_INDENT } };

    if (todo.is_done) {
        opts.color_text = .{ .color = .{ .r = 169, .g = 169, .b = 169 } };
    }

    try dvui.icon(@src(), "circle", if (todo.is_done) dvui.entypo.check else dvui.entypo.circle, .{ .id_extra = todo.id, .gravity_y = 0.5 });
    //not sure if better way of getting default font size
    var default_size = dvui.themeGet().font_body.lineHeightFactor(App.LINE_HEIGHT).size + 1; //13
    if (todo.id == app.current_selected_id) {
        opts.color_text = .{ .name = .accent };
        default_size += 2;
    }

    const font: dvui.Font = if (todo.is_done) .{ .size = default_size, .name = "VeraIt" } else .{ .size = default_size, .name = "Vera" };

    var ret = false;
    //if editing the current item, draw a text entry box instead of the item
    if (todo.id == app.current_selected_id and app.edit_enabled) {
        if (try renderTextBox(app, indent + 1))
            ret = true;
    } else {
        var tl = dvui.TextLayoutWidget.init(@src(), .{}, opts);
        try tl.install(.{});
        try tl.addText(todo.text, .{ .font = font });

        tl.processEvents();
        tl.deinit();
    }

    hbox.deinit();
    if (todo.id == app.current_selected_id and !app.edit_enabled) {
        if (try renderTextBox(app, indent + 1))
            ret = true;
    }

    for (todo.children.items) |child| {
        if (try renderTodoItem(app, app.getFromId(child).*, indent + 1))
            ret = true;
    }

    return ret;
}

//attempt to focus on the text entry box
fn focusTextEntry(app: *App) void {
    if (!(app.insert_enabled or app.edit_enabled) or app.is_text_focused) return;

    if (app.text_entry) |te| {
        dvui.focusWidget(te.wd.id, null, null);
        queue_focus_text_entry = false;
    }
}

// handle keyboard inputs
// down, j: move down to the next item
// up, k: move up to the prev item
// o: create a new item as a child to the current one
// i: edit the current item's text
// d: delete an item
// enter: submit the text edit or add a new item based on the mode if the text is not empty
// escape: exit text entry
fn process_user_input(app: *App) void {
    for (dvui.events()) |*e| {
        if (e.handled) continue;

        if (e.evt == .key and (e.evt.key.action == .down or e.evt.key.action == .repeat)) {
            if (!app.is_text_focused) {
                switch (e.evt.key.code) {
                    //navigation
                    .down, .j => app.moveToNextItem(),
                    .up, .k => app.moveToPrevItem(),
                    //toggle edit mode
                    .i => {
                        app.edit_enabled = true;
                        app.text_copied = false;
                        queue_focus_text_entry = true;
                    },
                    .o => {
                        app.insert_enabled = true;
                        queue_focus_text_entry = true;
                    },
                    .enter => app.toggleCurrentItemDone(),
                    .d => app.deleteItem(),

                    else => {},
                }

                switch (e.evt.key.code) {
                    .down, .j, .up, .k, .i, .o, .escape, .enter, .d => e.handled = true,
                    else => {},
                }
            } else {
                //handle events when over text box
                switch (e.evt.key.code) {
                    .escape => {
                        app.insert_enabled = false;
                        app.edit_enabled = false;
                        app.is_text_focused = false;
                        app.clearTextEntry();
                        e.handled = true;
                    },
                    .enter => {},
                    else => {},
                }
            }
        }
    }
}

test {
    std.testing.refAllDecls(@This());
}
