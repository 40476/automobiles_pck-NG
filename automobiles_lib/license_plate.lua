-- license_plate.lua (dofile-compatible)

-- Constants
LCD_WIDTH = 100
LCD_PADDING = 8
LINE_LENGTH = 12
NUMBER_OF_LINES = 1
LINE_HEIGHT = 14
CHAR_WIDTH = 5

-- Character map
license_plate_charmap = {}
local chars_file = io.open(minetest.get_modpath("automobiles_lib").."/characters", "r")
if chars_file then
    while true do
        local char = chars_file:read("*l")
        if not char then break end
        local img = chars_file:read("*l")
        chars_file:read("*l")
        license_plate_charmap[char] = img
    end
else
    minetest.log("error", "[license_plate] Character map file not found")
end

-- Split utility
function license_plate_split(s, pat)
    local st, g = 1, s:gmatch("()("..pat..")")
    return function()
        if st then
            local segs, seps, sep = st, g()
            st = sep and seps + #sep
            return s:sub(segs, (seps or 0) - 1)
        end
    end
end

-- Line creation
function license_plate_create_lines(text)
    local line = ""
    local tab = {}
    for word in license_plate_split(text, "%s") do
        if #line + #word + 1 <= LINE_LENGTH then
            line = line == "" and word or (line .. " " .. word)
        else
            table.insert(tab, line)
            line = word
            if #tab >= NUMBER_OF_LINES then break end
        end
    end
    if line ~= "" and #tab < NUMBER_OF_LINES then
        table.insert(tab, line)
    end
    return tab
end

-- Line rendering
function license_plate_generate_line(s, ypos)
    local i, parsed, width, chars = 1, {}, 0, 0
    while chars < LINE_LENGTH and i <= #s do
        local file
        local c1, c2 = s:sub(i, i), s:sub(i, i + 1)
        if license_plate_charmap[c1] then
            file = license_plate_charmap[c1]
            i = i + 1
        elseif license_plate_charmap[c2] then
            file = license_plate_charmap[c2]
            i = i + 2
        else
            file = license_plate_charmap[" "] or ""
            i = i + 1
        end
        if file then
            width = width + CHAR_WIDTH + 1
            table.insert(parsed, file)
            chars = chars + 1
        end
    end
    width = width - 1
    local xpos = math.floor((LCD_WIDTH - width) / 2)
    local texture = ""
    for _, img in ipairs(parsed) do
        texture = texture..":"..xpos..","..ypos.."="..img..".png"
        xpos = xpos + CHAR_WIDTH + 1
    end
    return texture
end

-- Texture generation
function license_plate_generate_texture(text)
    local lines = license_plate_create_lines(text)
    local texture = "[combine:"..LCD_WIDTH.."x"..LCD_WIDTH
    local ypos = math.floor((LCD_WIDTH - LINE_HEIGHT * NUMBER_OF_LINES) / 2)
    for _, line in ipairs(lines) do
        texture = texture .. license_plate_generate_line(line, ypos)
    end
    return texture
end

-- Entity registration
minetest.register_entity("automobiles_lib:license_plate", {
    visual = "upright_sprite",
    collisionbox = { 0, 0, 0, 0, 0, 0 },
    textures = {},
    on_activate = function(self)
        local meta = minetest.get_meta(self.object:get_pos())
        local plate_text = meta:get_string("plate_text") or "UNKNOWN"
        self.object:set_properties({
            textures = { license_plate_generate_texture(plate_text) }
        })
    end,
})
