-- File: radio_track_loader.lua

-- Scans a directory for files named like: genre__name__artist.ext
-- Returns a table of track metadata
function automobiles_lib.scan_radio_tracks(modname, subdir)
    local tracks = {}
    local modpath = minetest.get_modpath(modname)
    local fullpath = modpath .. "/" .. subdir

    local files = minetest.get_dir_list(fullpath, false)  -- false = files only

    for _, file in ipairs(files) do
        local genre, name, artist = file:match("^(.-)__(.-)__(.-)%.[%w]+$")
        if genre and name and artist then
            table.insert(tracks, {
                genre = genre,
                name = name,
                artist = artist,
                filename = file,
                path = fullpath .. "/" .. file
            })
        end
    end

    return tracks
end

-- Play sound for a single player
function automobiles_lib.radio_play(ent, track_name)
  if ent.radio_handle then
    minetest.sound_stop(ent.radio_handle)
    ent.radio_handle = nil
  end
  smartlog(ent.driver_name, track_name)
  ent.radio_handle = minetest.sound_play(track_name, {
    gain = 1.0,
    loop = false,
    to_player = ent.driver_name
  })

  -- Also play for passengers
  if ent._passenger_seats then
    for _, seat in pairs(ent._passenger_seats) do
      if seat.player_name then
        minetest.sound_play(track_name, {
          gain = 1.0,
          loop = false,
          to_player = seat.player_name
        })
      end
    end
  end
end

function automobiles_lib.radio_stop(ent)
  if ent.radio_handle then
    minetest.sound_stop(ent.radio_handle)
    ent.radio_handle = nil
  end
end

function automobiles_lib.filter_tracks(tracks, filter_type)
  local filtered = {}
  local seen = {}
  if filter_type == "artist" then
    for _, track in ipairs(tracks) do
      if not seen[track.artist] then
        table.insert(filtered, { name = track.artist, artist = track.artist })
        seen[track.artist] = true
      end
    end
  elseif filter_type == "genre" then
    for _, track in ipairs(tracks) do
      if not seen[track.genre] then
        table.insert(filtered, { name = track.genre, artist = "" })
        seen[track.genre] = true
      end
    end
  else
    return tracks
  end
  return filtered
end

function automobiles_lib.handle_radio_formspec_fields(name, ent, fields)
  -- Handle filter dropdown
  if fields.radio_filter then
    ent.radio_filter = fields.radio_filter
    local formspec_f = automobiles_lib.driver_formspec
    if ent._formspec_function then formspec_f = ent._formspec_function end
    formspec_f(name)
    return true
  end

  -- Handle track selection
  if fields.radio_track_list then
    local index = tonumber(fields.radio_track_list:match("CHG:(%d+)"))
    if index then
      local filtered = automobiles_lib.filter_tracks(ent.radio_tracks or {}, ent.radio_filter or "allsongs")
      local track = filtered[index]
      if track and track.filename then
        automobiles_lib.radio_play(ent, string.gsub(track.filename, "%.ogg", ""))
        ent.radio_selected_track = string.gsub(track.filename, "%.ogg", "")
      end
    end
    local formspec_f = automobiles_lib.driver_formspec
    if ent._formspec_function then formspec_f = ent._formspec_function end
    formspec_f(name)
    return true
  end

  -- Handle playback controls
  if fields.radio_play then
    if ent.radio_selected_track then
      automobiles_lib.radio_play(ent, ent.radio_selected_track)
    else
      minetest.chat_send_player(name, "No track selected.")
    end
    local formspec_f = automobiles_lib.driver_formspec
    if ent._formspec_function then formspec_f = ent._formspec_function end
    formspec_f(name)
    return true
  end

  if fields.radio_stop then
    automobiles_lib.radio_stop(ent)
    local formspec_f = automobiles_lib.driver_formspec
    if ent._formspec_function then formspec_f = ent._formspec_function end
    formspec_f(name)
    return true
  end

  if fields.radio_skip then
    -- Skip not yet implemented.
    minetest.chat_send_player(name, "Beans.")
    return true
  end

  if fields.radio_unskip then
    -- Unskip not yet implemented.
    minetest.chat_send_player(name, "Beans.")
    return true
  end

  return false
end

function automobiles_lib.get_radio_formspec_fragment(ent,x_offset)
  local selected_filter = ent.radio_filter or "allsongs"
  local selected_track = ent.radio_selected_track or ""
  local track_list = ""
  local x_offset = x_offset or 0

  local filtered_tracks = automobiles_lib.filter_tracks(ent.radio_tracks or {}, selected_filter)
  for i, track in ipairs(filtered_tracks) do
    track_list = track_list .. track.name .. (track.artist ~= "" and " - " .. track.artist or "") .. ","
  end


  return table.concat({
    "label[" .. tostring(x_offset+0.3) .. ",0.3;Radio]",
    "dropdown[" .. tostring(x_offset+0.3) .. ",0.4;3.5;radio_filter;artist,genre,allsongs;" .. selected_filter .. "]",
    "textlist[" .. tostring(x_offset+0.3) .. ",1.5;3.5,4.5;radio_track_list;" .. track_list .. "]",
    "button[" .. tostring(x_offset+0.3) .. ",6.2;1.5,1;radio_play;Play]",
    "button[" .. tostring(x_offset+2.2) .. ",6.2;1.5,1;radio_stop;Stop]",
    "button[" .. tostring(x_offset+0.3) .. ",7.2;1.5,1;radio_skip;Skip]",
    "button[" .. tostring(x_offset+2.2) .. ",7.2;1.5,1;radio_unskip;Unskip]"
  }, "")
end

--[[
radio implementing checklist
make formspec width automatic
before formspec definition
```
  local fs_width = <FORMSPEC_WIDTH>
  local fs_radio = ""
  if automobiles_lib.get_radio_formspec_fragment then
    fs_radio = automobiles_lib.get_radio_formspec_fragment(ent,fs_width)
    fs_width = fs_width + 4
  end
```
in the actual formspec: "size["..fs_width..",8]",
in formspec handling add:
```
if automobiles_lib.handle_radio_formspec_fields then
  automobiles_lib.handle_radio_formspec_fields(name, ent, fields)
end
```
append fs_radio to end of formspec (method varies)
]]--
