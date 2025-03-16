const dvui = @import("dvui");

const accent = Color{ .r = 203, .g = 75, .b = 22, .a = 0xff }; // s:gb.bright_orange
const err = Color{ .r = 0xcc, .g = 0x24, .b = 0x1d, .a = 0xff }; // s:gb.neutral_red
const text = Color{ .r = 0, .g = 43, .b = 60, .a = 0xff };
const text_press = Color{ .r = 143, .g = 121, .b = 70, .a = 0xff };
const fill = fill_control;
const fill_window = Color{ .r = 253, .g = 246, .b = 227, .a = 0xff };
const fill_control = Color{ .r = 253, .g = 246, .b = 227, .a = 0xff };
const fill_hover = border;
const fill_press = accent;
const border = Color{ .r = 0x83, .g = 0xa5, .b = 0x98, .a = 0xff }; // s:gb.bright_blue
const size = 16;

const Color = dvui.Color;
const Font = dvui.Font;
const Theme = dvui.Theme;
const Options = dvui.Options;

pub const theme = Theme{
    .name = "solar-light",
    .dark = false,

    .font_body = .{ .size = size, .name = "Aleo" },
    .font_heading = .{ .size = size, .name = "AleoBd" },
    .font_caption = .{ .size = size * 0.8, .name = "Aleo" },
    .font_caption_heading = .{ .size = size * 0.8, .name = "AleoBd" },
    .font_title = .{ .size = size * 2, .name = "Aleo" },
    .font_title_1 = .{ .size = size * 1.8, .name = "AleoBd" },
    .font_title_2 = .{ .size = size * 1.6, .name = "AleoBd" },
    .font_title_3 = .{ .size = size * 1.4, .name = "AleoBd" },
    .font_title_4 = .{ .size = size * 1.2, .name = "AleoBd" },

    .color_accent = accent,
    .color_err = err,
    .color_text = text,
    .color_text_press = text_press,
    .color_fill = fill,
    .color_fill_window = fill_window,
    .color_fill_control = fill_control,
    .color_fill_hover = fill_hover,
    .color_fill_press = fill_press,
    .color_border = border,

    .style_accent = Options{
        .color_accent = .{ .color = Color.alphaAdd(accent, accent) },
        .color_text = .{ .color = Color.alphaAdd(accent, text) },
        .color_text_press = .{ .color = Color.alphaAdd(accent, text_press) },
        .color_fill = .{ .color = Color.alphaAdd(accent, fill) },
        .color_fill_hover = .{ .color = Color.alphaAdd(accent, fill_hover) },
        .color_fill_press = .{ .color = Color.alphaAdd(accent, fill_press) },
        .color_border = .{ .color = Color.alphaAdd(accent, border) },
    },

    .style_err = Options{
        .color_accent = .{ .color = Color.alphaAdd(err, accent) },
        .color_text = .{ .color = Color.alphaAdd(err, text) },
        .color_text_press = .{ .color = Color.alphaAdd(err, text_press) },
        .color_fill = .{ .color = Color.alphaAdd(err, fill) },
        .color_fill_hover = .{ .color = Color.alphaAdd(err, fill_hover) },
        .color_fill_press = .{ .color = Color.alphaAdd(err, fill_press) },
        .color_border = .{ .color = Color.alphaAdd(err, border) },
    },
};
