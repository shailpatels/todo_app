const dvui = @import("dvui");
const std = @import("std");

const assert = std.debug.assert;

//A Todo item
pub const Item = struct {
    text: []u8,
    parent: ?u32,
    children: std.ArrayListUnmanaged(u32),
    is_done: bool = false,

    //next item to visit
    next: ?u32 = null,
    prev: ?u32 = null,

    id: u32,

    //return the id of the next item from this one
    pub fn nextItem(self: *Item, app: *App) u32 {
        //return next index or go back to start
        return self.nextHelper(app) orelse 0;
    }

    //return the id of the previous item from this one
    pub fn prevItem(self: *Item, app: *App) u32 {
        if (self.prev) |p| {
            var item_id = p;
            var item = app.getFromId(item_id);
            while (item.children.items.len > 0) {
                item_id = item.children.items[@intCast(item.children.items.len - 1)];
                item = app.getFromId(item_id);
            }

            return item_id;
        } else {
            return self.parent orelse @intCast(app.todo_items.items.len - 1);
        }
    }

    //add a child item to a source item
    pub fn addChild(self: *Item, child_id: u32, app: *App) !void {
        var child = app.getFromId(child_id);

        child.parent = self.id;
        if (self.children.items.len > 0) {
            var last_child = app.getFromId(self.children.items[@intCast(self.children.items.len - 1)]);
            last_child.next = child_id;
            child.prev = last_child.id;
        }

        try self.children.append(app.allocator, child_id);
    }

    pub fn delete(self: *Item, app: *App) void {
        //cannot delete root
        if (self.parent == null) return;

        if (self.prev) |p| app.getFromId(p).next = self.next;
        if (self.next) |n| app.getFromId(n).prev = self.prev;

        if (self.parent) |p| {
            var parent = app.getFromId(p);
            for (parent.children.items, 0..) |item, idx| {
                if (app.getIndexFromId(app.getItem(item).id) == self.id) {
                    _ = parent.children.swapRemove(idx);
                    break;
                }
            }
        }

        self.deleteHelper(app);
    }

    //update this items text
    pub fn updateText(self: *Item, new_text: []const u8, allocator: std.mem.Allocator) !void {
        if (new_text.len != self.text.len)
            self.text = try allocator.realloc(self.text, new_text.len);

        @memcpy(self.text, new_text);
    }

    //toggle if the item is done or not, updates children and parents
    pub fn toggleStatus(self: *Item, new_status: ?bool, app: *App) void {
        self.is_done = if (new_status) |status| status else !self.is_done;
        self.toggleStatusHelper(self.is_done, app);
    }

    fn toggleStatusHelper(self: *Item, new_status: bool, app: *App) void {
        for (self.children.items) |child_id|
            app.getFromId(child_id).toggleStatus(new_status, app);

        self.toggle_parent_status(app);
    }

    //if this items parent has all its child items marked as done, the parent should also be done
    fn toggle_parent_status(self: *Item, app: *App) void {
        if (self.parent == null) return;

        var parent = app.getFromId(self.parent.?);
        var all_done = true;
        for (parent.children.items) |child_id| {
            if (!app.getFromId(child_id).is_done) all_done = false;
        }

        parent.is_done = all_done;
        parent.toggle_parent_status(app);
    }

    fn deleteHelper(self: *Item, app: *App) void {
        for (self.children.items) |child|
            app.getFromId(child).deleteHelper(app);

        self.children.clearAndFree(app.allocator);
        app.allocator.free(self.text);

        const idx_cpy = app.getIndexFromId(self.id);
        assert(app.id_idx_map.remove(self.id));
        //now whatever used to be at the end of the list now is at idx_cpy
        _ = app.todo_items.swapRemove(idx_cpy);

        //self now points to whatever was at the end of the array
        app.id_idx_map.put(app.allocator, self.id, idx_cpy) catch {};
    }

    fn nextHelper(self: *Item, app: *App) ?u32 {
        if (self.children.items.len > 0) {
            return self.children.items[0];
        } else if (self.next) |n| {
            return n;
        } else {
            var parent = self.parent;
            while (parent) |par_id| {
                const par = app.getFromId(par_id);
                if (par.next) |n| return n;

                parent = par.parent;
            }

            return null;
        }
    }
};

pub const App = struct {
    pub const LINE_HEIGHT = 1.2;
    pub const LEFT_INDENT = 12.0;
    pub const TEXT_BUFFER = 1024;

    const SaveData = struct {
        todo_items: std.ArrayListUnmanaged(Item),
        keys: std.ArrayListUnmanaged(u32),
        vals: std.ArrayListUnmanaged(u32),
    };

    //mem buffer for text entry
    text_entry_buff: [App.TEXT_BUFFER]u8 = [_]u8{0} ** App.TEXT_BUFFER,
    allocator: std.mem.Allocator,
    todo_items: std.ArrayListUnmanaged(Item),

    current_selected_id: u32 = 0,
    save_file: std.fs.File = undefined,

    insert_enabled: bool = false,
    edit_enabled: bool = false,
    is_text_focused: bool = false,
    text_copied: bool = false,
    is_running: bool = true,

    text_entry: ?*dvui.TextEntryWidget = null,

    //mapping of ids to index, initially the id and index is the same, but deleting can change this
    //the position of an item can change but the id will always point to the current end
    id_idx_map: std.AutoHashMapUnmanaged(u32, u32),
    id_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) !App {
        var app = App{
            .allocator = allocator,
            .todo_items = try std.ArrayListUnmanaged(Item).initCapacity(allocator, 10),
            .id_idx_map = std.AutoHashMapUnmanaged(u32, u32){},
        };

        //create a root node for all items to be under
        try app.todo_items.append(app.allocator, Item{
            .text = &.{},
            .children = try std.ArrayListUnmanaged(u32).initCapacity(app.allocator, 5),
            .parent = null,
            .id = 0,
        });

        app.current_selected_id = 0;
        try app.id_idx_map.put(app.allocator, 0, 0);

        return app;
    }

    pub fn deinit(self: *App) void {
        defer self.todo_items.deinit(self.allocator);
        defer self.id_idx_map.deinit(self.allocator);

        for (self.todo_items.items) |*item| {
            self.allocator.free(item.text);
            item.children.deinit(self.allocator);
        }
    }

    //check to see if a file to save todo items exists, if not create it
    pub fn initializeFile(self: *App) !void {
        const file_name = "data";
        self.save_file = std.fs.cwd().openFile(file_name, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => try std.fs.cwd().createFile(file_name, .{ .read = true }),
            else => return err,
        };
    }

    pub fn save(self: *App) !void {
        try self.empty_file();

        const indent: u32 = 0;
        try self.write_children(self.getFromId(0), indent);
    }

    fn write_children(self: *App, parent: *const Item, indent: u32) !void {
        for (parent.children.items) |c_id| {
            const child = self.getFromId(c_id);

            try self.write_start_item(child, indent);
            _ = try self.save_file.write(child.text);
            _ = try self.save_file.write("\n");
            try self.write_children(child, indent + 1);
        }
    }

    fn write_indent(self: *App, indent: u32) !void {
        for (0..indent * 4) |_| {
            _ = try self.save_file.write(" ");
        }
    }

    fn write_start_item(self: *App, item: *const Item, indent: u32) !void {
        _ = try self.write_indent(indent);
        _ = try self.save_file.write("- [");
        const chr = if (item.is_done) "X" else " ";
        _ = try self.save_file.write(chr);
        _ = try self.save_file.write("] ");
    }

    //clear the file to re-write, not sure if there's a better way for this
    fn empty_file(self: *App) !void {
        const stat = try self.save_file.stat();
        try self.save_file.seekTo(0);
        var buffer = try std.ArrayList(u8).initCapacity(self.allocator, stat.size);
        _ = buffer.addManyAtAssumeCapacity(0, stat.size);
        defer buffer.deinit();

        assert(buffer.items.len == stat.size);
        try self.save_file.writeAll(buffer.items);
        try self.save_file.seekTo(0);
    }

    pub fn load(self: *App) !void {
        const stat = try self.save_file.stat();
        const buffer = try self.save_file.readToEndAlloc(self.allocator, stat.size);
        defer self.allocator.free(buffer);

        var line_iter = std.mem.splitScalar(u8, buffer, '\n');
        self.current_selected_id = 0;
        defer self.current_selected_id = 0;

        var last_item_id: u32 = 0;
        var last_indent: usize = 0;
        while (line_iter.next()) |line| {
            if (line.len == 0) continue;

            //calculate indent
            var i: usize = 0;
            var chr = line[0];
            while (chr == ' ' and i < line.len) : (i += 1) {
                chr = line[i];
            }

            if (i == 0) {
                //top level item
                self.current_selected_id = 0;
                last_item_id = try self.addNewItems(line[6..line.len]);
                var last_item = self.getFromId(last_item_id);
                last_item.is_done = line[3] == 'X';
            } else {
                const level = if (i == 0) 0 else (i - 1) / 4;
                const last_level = if (last_indent == 0) 0 else (last_indent - 1) / 4;
                const nesting = (i - 1) + 6;

                if (level == last_level + 1) {
                    self.current_selected_id = last_item_id;
                    last_item_id = try self.addNewItems(line[nesting..line.len]);
                    var last_item = self.getFromId(last_item_id);

                    last_item.is_done = line[nesting - 3] == 'X';
                } else if (level <= last_level) {
                    self.current_selected_id = last_item_id;
                    const diff = last_level - level;

                    self.moveToParent();
                    for (0..diff) |_| {
                        self.moveToParent();
                    }

                    last_item_id = try self.addNewItems(line[nesting..line.len]);
                    var last_item = self.getFromId(last_item_id);

                    last_item.is_done = line[nesting - 3] == 'X';
                } else {
                    std.debug.print("my indent {}, last indent {}\n", .{ level, last_level });
                    std.debug.print("{s}\n", .{line});
                    @panic("unhandled load");
                }
            }

            last_indent = i;
        }
    }

    //remove text from the text entry box
    pub fn clearTextEntry(self: *App) void {
        if (self.text_entry == null) return;

        self.text_entry.?.len = 0;
        self.text_entry_buff = std.mem.zeroes([App.TEXT_BUFFER]u8);
    }

    //return whatevers typed in the text entry box if its open
    pub fn getText(self: *App) ?[]const u8 {
        if (self.text_entry == null) return null;

        var te = self.text_entry.?;
        return te.text[0..te.len];
    }

    //add a new todo item, returns the id of the new item created
    pub fn addNewItems(self: *App, text: []const u8) !u32 {
        //the index where the new item will be at
        try self.todo_items.append(self.allocator, Item{
            .text = try self.allocator.alloc(u8, text.len),
            .children = try std.ArrayListUnmanaged(u32).initCapacity(self.allocator, 5),
            .parent = undefined,
            .id = undefined,
        });

        const new_idx: u32 = @intCast(self.todo_items.items.len - 1);
        const new_id = self.getNewId();
        try self.id_idx_map.put(self.allocator, new_id, new_idx);
        var last_item: *Item = self.getItem(new_idx);

        last_item.id = new_id;
        @memcpy(last_item.text, text);

        try self.getFromId(self.current_selected_id).addChild(new_id, self);

        assert(last_item.id == new_id);
        assert(last_item.parent != null);

        return last_item.id;
    }

    pub fn deleteItem(self: *App) void {
        const id_to_del = self.current_selected_id;
        //move to prev node since current will be deleted
        self.moveToPrevItem();
        self.getFromId(id_to_del).delete(self);
    }

    //return an id and increment the count
    fn getNewId(self: *App) u32 {
        self.id_count += 1;
        return self.id_count;
    }

    //given an ID, return an item
    //this is the function that should be used for getting todo items
    pub fn getFromId(self: *App, id: u32) *Item {
        return self.getItem(self.getIndexFromId(id));
    }

    //given an id return the index in the todo_items list, assumes index is present
    fn getIndexFromId(self: *App, id: u32) u32 {
        const idex = self.id_idx_map.get(id);
        assert(idex != null);

        return self.id_idx_map.get(id).?;
    }

    //given an index, return an item from the arrayList
    fn getItem(self: *App, idx: anytype) *Item {
        assert(idx >= 0);
        assert(idx < self.todo_items.items.len);
        return &(self.todo_items.items[idx]);
    }

    //move down the list of items
    pub fn moveToNextItem(self: *App) void {
        self.current_selected_id = self.getFromId(self.current_selected_id).nextItem(self);
    }

    //move up the list to the previouslly selected item
    pub fn moveToPrevItem(self: *App) void {
        self.current_selected_id = self.getFromId(self.current_selected_id).prevItem(self);
    }

    pub fn moveToParent(self: *App) void {
        const current = self.getFromId(self.current_selected_id);
        self.current_selected_id = current.parent orelse 0;
    }

    //toggle the done status of the current item
    pub fn toggleCurrentItemDone(self: *App) void {
        self.getFromId(self.current_selected_id).toggleStatus(null, self);
    }
};

test "moving top level items" {
    const allocator = std.testing.allocator;

    var app = try App.init(allocator);
    defer app.deinit();

    assert(app.todo_items.items.len == 1);
    assert(app.todo_items.items[0].id == 0);
    assert(app.todo_items.items[0].parent == null);

    for (0..20) |idx| {
        const buf = try allocator.alloc(u8, 20);
        defer allocator.free(buf);
        const res = try std.fmt.bufPrint(buf, "item {d}", .{idx});

        try std.testing.expectEqual(idx + 1, try app.addNewItems(res));
        try std.testing.expectEqualStrings(res, app.todo_items.items[app.todo_items.items.len - 1].text);
    }

    assert(app.todo_items.items.len == 21);
    assert(app.todo_items.items[0].children.items.len == 20);

    for (app.todo_items.items[1..]) |item| try std.testing.expectEqual(0, item.parent.?);
    for (app.todo_items.items, 0..) |item, idx| try std.testing.expectEqual(idx, item.id);
    for (app.todo_items.items[2..], 2..) |item, idx| try std.testing.expectEqual(idx - 1, item.prev.?);

    try std.testing.expectEqual(0, app.current_selected_id);
    app.moveToNextItem();
    try std.testing.expectEqual(1, app.current_selected_id);
    app.moveToNextItem();
    try std.testing.expectEqual(2, app.current_selected_id);

    app.deleteItem();
    try std.testing.expectEqual(null, app.id_idx_map.get(2));
    try std.testing.expectEqual(2, app.id_idx_map.get(20));
    try std.testing.expectEqual(1, app.current_selected_id);
    app.toggleCurrentItemDone();
    try std.testing.expectEqual(true, app.getFromId(1).is_done);
}
