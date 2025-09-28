-- File: init.lua

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

-- Play sound for a single player (with full handle management)
function automobiles_lib.radio_play(ent, track_name)
  if not ent or not track_name then return end  -- Safety: Bail if bad inputs

  -- Stop any existing sounds first (clean old state; safe even if radio_handles is nil)
  automobiles_lib.radio_stop(ent)

  -- NOW initialize handles table for new playback (after cleanup, so it stays a table)
  ent.radio_handles = ent.radio_handles or {}

  smartlog(ent.driver_name, "DEBUG: radio_play started for track '" .. tostring(track_name) .. "' - ent.driver_name: " .. tostring(ent.driver_name))

  smartlog(ent.driver_name, track_name)

  -- Play for driver IMMEDIATELY and store handle
  local driver_handle = minetest.sound_play(track_name, {
    gain = 1.0,
    loop = false,
    to_player = ent.driver_name
  })
  ent.radio_handle = driver_handle  -- Legacy compatibility
  ent.radio_handles[ent.driver_name] = driver_handle

  smartlog(ent.driver_name, "DEBUG: Driver '" .. ent.driver_name .. "' handle: " .. tostring(driver_handle) .. " (type: " .. type(driver_handle) .. ", nil? " .. tostring(driver_handle == nil) .. ")")

  -- Collect passenger names (set for dedup)
  local passengers = {}  -- Set: passengers[name] = true
  local passenger_list = {}  -- For order
  -- Legacy _passenger
  if ent._passenger and ent._passenger ~= ent.driver_name then
    if not passengers[ent._passenger] then
      passengers[ent._passenger] = true
      table.insert(passenger_list, ent._passenger)
    end
    smartlog(ent.driver_name, "DEBUG: Collected _passenger '" .. ent._passenger .. "'")
  end
  -- Multi-passengers
  if ent._passengers then
    local max_seats = ent._seat_pos and #ent._seat_pos or 100
    for i = 2, max_seats do
      local pname = ent._passengers[i]
      if not pname then break end
      if pname ~= ent.driver_name and minetest.get_player_by_name(pname) then
        if not passengers[pname] then
          passengers[pname] = true
          table.insert(passenger_list, pname)
        end
        smartlog(ent.driver_name, "DEBUG: Collected _passengers[" .. i .. "] '" .. pname .. "'")
      else
        smartlog(ent.driver_name, "DEBUG: Skipped _passengers[" .. i .. "] (nil, driver, or offline)")
      end
    end
  end

  smartlog(ent.driver_name, "DEBUG: Total unique passengers: " .. #passenger_list)

  -- Play for each passenger with DELAY for client sync + retry if nil
  for _, pname in ipairs(passenger_list) do
    -- First attempt: Immediate
    local handle = minetest.sound_play(track_name, {
      gain = 1.0,
      loop = false,
      to_player = pname
    })
    ent.radio_handles[pname] = handle

    smartlog(ent.driver_name, "DEBUG: Passenger '" .. pname .. "' first handle: " .. tostring(handle) .. " (type: " .. type(handle) .. ")")

    -- If nil, RETRY after short delay (client may need time)
    if handle == nil then
      minetest.after(0.2, function()
        if minetest.get_player_by_name(pname) and ent.radio_handles and ent.radio_handles[pname] == nil then
          local retry_handle = minetest.sound_play(track_name, {
            gain = 1.0,
            loop = false,
            to_player = pname
          })
          ent.radio_handles[pname] = retry_handle
          smartlog(ent.driver_name, "DEBUG: RETRY for '" .. pname .. "' succeeded: " .. tostring(retry_handle) .. " (type: " .. type(retry_handle) .. ")")
        end
      end)
    end
  end

  smartlog(ent.driver_name, "DEBUG: radio_play ended - handles table keys: " .. dump(ent.radio_handles))

  ent.radio_selected_track = string.gsub(track_name, "%.ogg", "")
end

function automobiles_lib.radio_stop(ent)
  if not ent then return end  -- Safety

  local was_playing_track = ent.radio_selected_track or "unknown"
  local total_handles = 0
  local successful_stops = 0

  -- Stop driver's handle (legacy)
  if ent.radio_handle then
    smartlog(ent.driver_name, "DEBUG: radio_stop - stopping driver handle for '" .. was_playing_track .. "' (" .. tostring(ent.radio_handle) .. ")")
    minetest.sound_stop(ent.radio_handle)
    ent.radio_handle = nil
    successful_stops = successful_stops + 1
  else
    smartlog(ent.driver_name, "DEBUG: radio_stop - no driver handle to stop")
  end

  -- Stop all handles from table (guarded against nil)
  if ent.radio_handles then
    local keys = {}
    for pname, handle in pairs(ent.radio_handles) do
      table.insert(keys, pname)
    end
    total_handles = #keys
    smartlog(ent.driver_name, "DEBUG: radio_stop - found " .. total_handles .. " handles to check for '" .. was_playing_track .. "': " .. dump(keys))

    for pname, handle in pairs(ent.radio_handles) do
      if handle and type(handle) == "number" then  -- Explicit: Ensure it's a valid number handle
        smartlog(ent.driver_name, "DEBUG: radio_stop - stopping valid handle for '" .. pname .. "' (" .. tostring(handle) .. ")")
        minetest.sound_stop(handle)
        successful_stops = successful_stops + 1
      else
        smartlog(ent.driver_name, "DEBUG: radio_stop - skipping '" .. pname .. "' (invalid or nil handle: " .. tostring(handle) .. ", type: " .. type(handle) .. ")")
      end
      ent.radio_handles[pname] = nil  -- Clear always
    end
    ent.radio_handles = nil  -- Full cleanup
  else
    smartlog(ent.driver_name, "DEBUG: radio_stop - no radio_handles table at all")
  end

  ent.radio_selected_track = nil  -- Reset
  smartlog(ent.driver_name, "DEBUG: radio_stop complete for '" .. was_playing_track .. "' - checked " .. total_handles .. " handles, successful stops: " .. successful_stops)
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
