local S = automobiles_lib.S
local key_target_id = key_target_id or {}  -- Global temp storage: player_name -> car_id (ID-based for reliability)
local player_bookmarks = {}
local player_selected_bookmarks = {}

-- Helper to auto-clear stale references (your 15s timeout)
local function clear_key_ref(player_name)
  minetest.after(15, function()
    if key_target_id[player_name] then
      key_target_id[player_name] = nil
      minetest.log("action", "Auto-cleared key ref for player " .. player_name)
    end
  end)
end

local function show_copyable_text(player_name, label, content)
  local fs = table.concat({
    "formspec_version[4]",
    "size[10,6]",
    "label[0.5,0.5;" .. minetest.formspec_escape(label) .. "]",
    "textarea[0.5,1;9,4.5;copied_text;;" .. minetest.formspec_escape(content) .. "]",
    "button[4,5.6;2,1;close_copy;Close]"
  }, "")
  minetest.show_formspec(player_name, "automobiles_lib:copy_text", fs)
end


function automobiles_lib.getCarFromPlayer(player, self)
  local seat = player:get_attach()
  if seat then
    local car = seat:get_attach()
    if car then
      return car
    else
      return seat
    end
  end
  return nil
end

function automobiles_lib.add_bookmark(player_name, name, pos)
  player_bookmarks[player_name] = player_bookmarks[player_name] or {}
  for i, bookmark in ipairs(player_bookmarks[player_name]) do
    if bookmark.name == name then
      player_bookmarks[player_name][i] = { name = name, pos = pos }
      return
    end
  end
  table.insert(player_bookmarks[player_name], { name = name, pos = pos })
end

function automobiles_lib.remove_bookmark(player_name, name)
  if not player_bookmarks[player_name] then return end
  for i, bookmark in ipairs(player_bookmarks[player_name]) do
    if bookmark.name == name then
      table.remove(player_bookmarks[player_name], i)
      if player_selected_bookmarks[player_name] and player_selected_bookmarks[player_name].name == name then
        player_selected_bookmarks[player_name] = nil
      end
      return
    end
  end
end

function automobiles_lib.remove_bookmark(player_name, name)
  if not player_bookmarks[player_name] then return end
  for i, bookmark in ipairs(player_bookmarks[player_name]) do
    if bookmark.name == name then
      table.remove(player_bookmarks[player_name], i)
      if player_selected_bookmarks[player_name] and player_selected_bookmarks[player_name].name == name then
        player_selected_bookmarks[player_name] = nil
      end
      return
    end
  end
end


function automobiles_lib.get_bookmark(player_name, name)
  if not player_bookmarks[player_name] then return nil end
  for _, bookmark in ipairs(player_bookmarks[player_name]) do
    if bookmark.name == name then return bookmark end
  end
  return nil
end

function automobiles_lib.get_bookmark(player_name, name)
  if not player_bookmarks[player_name] then return nil end
  for _, bookmark in ipairs(player_bookmarks[player_name]) do
    if bookmark.name == name then return bookmark end
  end
  return nil
end


function automobiles_lib.driver_formspec(name)
  local player = minetest.get_player_by_name(name)
  if not player then return end

  local vehicle_obj = automobiles_lib.getCarFromPlayer(player)
  if not vehicle_obj then return end

  local ent = vehicle_obj:get_luaentity()
  if not ent then return end

  local yaw = ent._yaw_by_mouse and "true" or "false"
  local autodrive_state = ent._autodrive_active and "true" or "false"
  local force_facing_dir = ent._force_facing_dir or false
  
  -- Build bookmark list
  local bookmark_list = ""
  local selected_idx = 0
  local has_selection = false
  if player_bookmarks[name] then
    for i, bookmark in ipairs(player_bookmarks[name]) do
      bookmark_list = bookmark_list .. bookmark.name .. ","
      if player_selected_bookmarks[name] and player_selected_bookmarks[name].name == bookmark.name then
        selected_idx = i - 1
        has_selection = true
      end
    end
    if #bookmark_list > 0 then
      bookmark_list = bookmark_list:sub(1, -2)
    end
  end
  local fs_width = 10.5
  local fs_radio = ""
  if automobiles_lib.get_radio_formspec_fragment then
    fs_radio = automobiles_lib.get_radio_formspec_fragment(ent,fs_width)
    fs_width = fs_width + 4
  end
  local fs = table.concat({
    "formspec_version[3]",
    "size["..fs_width..",8]",
    "label[1,0.3;" .. S("Vehicle Controls") .. "]",
    "button[1,1.0;4,1;go_out;" .. S("Go Offboard") .. "]",
    "button[1,2.5;4,1;lights;" .. S("Lights") .. "]",
    "checkbox[1,4.0;autodrive;" .. S("Autonomous Drive") .. ";" .. autodrive_state .. "]",
    "checkbox[1,4.4;yaw;" .. S("Direction by mouse") .. ";" .. yaw .. "]",
    "checkbox[1,4.8;force_facing_dir;" .. S("Lock facing to car") .. ";".. tostring(force_facing_dir) .."]",
    "field[1,5.7;3,1;bookmark_name;" .. S("Bookmark Name") .. ";]",
    "button[1,6.7;1.5,1;add_bookmark;" .. S("Add") .. "]",
    "button[2.5,6.7;1.5,1;remove_bookmark;" .. S("Del") .. "]",
    "label[6,0.5;" .. S("Bookmarks") .. "]",
    "textlist[6,1;3.5,5.5;bookmark_list;" .. bookmark_list .. ";" .. tostring(selected_idx) .. "]",
    "button[6,6.7;3.5,1;goto_bookmark;" .. S("Set Target") .. "]",
     fs_radio
  }, "")
  
  --minetest.chat_send_all(dump(bookmark_list))
  minetest.show_formspec(name, "automobiles_lib:driver_main", fs)
  --show_copyable_text(name, 'bruh', dump(fs_radio))
end

function automobiles_lib.show_key_formspec(player_name, car_id, key_name)
  local S = automobiles_lib.S
  local ent = automobiles_lib.get_car_by_id(car_id)
  if ent.object:get_pos() == nil then
    minetest.chat_send_player(player_name, S("Paired car (ID: @1) not found—may be destroyed or unloaded. Re-pair/re-place/re-load or go near the car.", car_id))
    return
  end
  if not ent or not ent.owner then
    minetest.chat_send_player(player_name, S("Invalid car ID @1.", car_id))
    return
  end
  local is_owner = player_name == ent.owner
  local locked_text = ent._locked and S("Locked") or S("Unlocked")
  local car_color = ent._color or "#FFFFFF"
  local fs = table.concat({
    "formspec_version[3]",
    "size[8,6]",  -- Your updated size
    "label[1,0.5;" .. S("Car Key Functions (ID: @1)", car_id) .. "]",
    "button[1,1;2,1;toggle_lock;" .. locked_text .. "]",
  }, "")

  if key_name:find("fancy") or key_name:find("advanced") then
    fs = fs .. "button[1,2.2;2,1;panic;" .. S("Panic (Horn)") .. "]"
  end
  if key_name:find("advanced") then
    fs = fs .. "button[3.5,3.4;4,1;locate;Location: (X:" .. math.floor(ent.object:get_pos().x) .. 
                                                  ", Y:" .. math.floor(ent.object:get_pos().y) ..
                                                  ", z:" .. math.floor(ent.object:get_pos().z) ..")]"
  end
  if is_owner then 
      fs = fs .. "button[1,3.4;2,1;unpair;" .. S("Unpair Key") .. "]"
  end
  -- Color preview (your addition)
  local meta_color = ""  -- Fetch from wielded later if needed
  fs = fs .. "image[1,4.6;2,1;key_ui_swatch.png^[colorize:" .. car_color .. ":200]"
  -- this is broken --- IGNORE ---
  -- ADDED: Key texture colorization preview (tinted based on car color)
  -- local key_base_images = {
    -- basic_key = "basic_key1.png",  -- Adjust to your base key textures
    -- fancy_key = "fancy_key.png",
    -- advanced_key = "advanced_key.png"
  -- }
  -- local key_short = key_name:gsub("automobiles_lib:", ""):gsub("_key", "")
  -- local key_base = key_base_images[key_short] or "basic_key1.png"
  -- local key_tint = key_base .. "^[colorize:" .. car_color .. ":200"  -- RRGGBB without #, alpha 200
  -- fs = fs .. "image[2.5,0.5;1,1;" .. key_tint .. "] label[3.5,0.8;Key Preview]"

  minetest.show_formspec(player_name, "automobiles_lib:key_menu", fs)
  -- Store ID for fields handling
  key_target_id[player_name] = car_id
  -- clear_key_ref(player_name)  -- Your 15s auto-clear
end

-- Single, complete on_player_receive_fields handler
minetest.register_on_player_receive_fields(function(player, formname, fields)
  local name = player:get_player_name()

  if formname == "automobiles_lib:driver_main" then
    local car_obj = automobiles_lib.getCarFromPlayer(player)
    if car_obj then
      local ent = car_obj:get_luaentity()
      if ent then
        if fields.autodrive then
          if ent._autodrive_active then
            ent._autodrive_active = false
            if autodrive then autodrive.deactivate(ent) end
          else
            if autodrive and player_selected_bookmarks[name] then
              autodrive.set_target(ent, player_selected_bookmarks[name].pos)
              minetest.chat_send_player(name, S("Navigating to bookmark '@1' at @2",
                player_selected_bookmarks[name].name,
                minetest.pos_to_string(player_selected_bookmarks[name].pos)))
            end
            ent._autodrive_active = true
            if autodrive then autodrive.activate(ent) end
          end
          automobiles_lib.driver_formspec(name)
          return true
        end

        if fields.add_bookmark and fields.bookmark_name and fields.bookmark_name ~= "" then
          local pos = ent.object:get_pos()
          automobiles_lib.add_bookmark(name, fields.bookmark_name, pos)
          minetest.chat_send_player(name, S("Bookmark '@1' added at @2", fields.bookmark_name, minetest.pos_to_string(pos)))
          automobiles_lib.driver_formspec(name)
          return true
        end

        if fields.remove_bookmark and fields.bookmark_name and fields.bookmark_name ~= "" then
          automobiles_lib.remove_bookmark(name, fields.bookmark_name)
          minetest.chat_send_player(name, S("Bookmark '@1' removed", fields.bookmark_name))
          automobiles_lib.driver_formspec(name)
          return true
        end

        if fields.bookmark_list then
          local list_event = fields.bookmark_list
          if string.find(list_event, "CHG:") then
            local index_str = string.match(list_event, "CHG:(%d+)")
            if index_str then
              local selected_index = tonumber(index_str)
              if selected_index and player_bookmarks[name] then
                local actual_index = selected_index
                if player_bookmarks[name][actual_index] then
                  player_selected_bookmarks[name] = player_bookmarks[name][actual_index]
                end
              end
            end
            automobiles_lib.driver_formspec(name)
            return true
          end
        end

        if fields.goto_bookmark then
          if player_selected_bookmarks[name] then
            local bookmark = player_selected_bookmarks[name]
            if autodrive then
              autodrive.set_target(ent, bookmark.pos)
              minetest.chat_send_player(name, S("Target set to bookmark '@1' at @2",
                bookmark.name, minetest.pos_to_string(bookmark.pos)))
            end
          else
            minetest.chat_send_player(name, S("Please select a bookmark first"))
          end
          automobiles_lib.driver_formspec(name)
          return true
        end

        if fields.go_out then
          if ent._passenger then
            local pax_obj = minetest.get_player_by_name(ent._passenger)
            local dettach_pax_f = automobiles_lib.dettach_pax
            if ent._dettach_pax then dettach_pax_f = ent._dettach_pax end
            dettach_pax_f(ent, pax_obj)
            minetest.close_formspec(name, "automobiles_lib:driver_main")
          end
          ent._is_flying = 0
          local dettach_f = automobiles_lib.dettach_driver
          if ent._dettach then dettach_f = ent._dettach end
          dettach_f(ent, player)
        end
        if fields.lights then
          ent._show_lights = not ent._show_lights
          minetest.close_formspec(name, "automobiles_lib:driver_main")
        end
        if fields.yaw then
          ent._yaw_by_mouse = not ent._yaw_by_mouse
          minetest.close_formspec(name, "automobiles_lib:driver_main")
        end
        if fields.force_facing_dir then
          if ent._force_facing_dir == true then
              ent._force_facing_dir = false
          else
              ent._force_facing_dir = true
              ent._yaw_by_mouse = false
          end
          minetest.close_formspec(name, "automobiles_lib:driver_main")
        end
        if fields.autodrive then
          if ent._autodrive_active then
            if autodrive then autodrive.deactivate(ent) end
            ent._autodrive_active = false
          else
            if autodrive then autodrive.activate(ent) end
            ent._autodrive_active = true
          end
        end
        if automobiles_lib.handle_radio_formspec_fields then
          automobiles_lib.handle_radio_formspec_fields(name, ent, fields)
        end
        return true
      end
    end
    return true
  end

  if formname == "automobiles_lib:key_menu" then
    -- If no actionable fields were pressed, assume the player closed the form
    if fields.quit then
      key_target_id[name] = nil
      return true
    end
    local car_id = key_target_id[name]
    if not car_id then
      minetest.chat_send_player(name, "No stored car ID. Repunch the car to reopen.")
      return true
    end

    local ent = automobiles_lib.get_car_by_id(car_id)  -- Fresh lookup
    if not ent or not ent.owner or ent.owner == "" then
      minetest.chat_send_player(name, S("Car reference lost for ID @1 (try again).", car_id))
      key_target_id[name] = nil
      if car_registry then car_registry[car_id] = nil end  -- Purge stale
      return true
    end

    local wielded = player:get_wielded_item()
    if not wielded or not wielded:get_name():match("^automobiles_lib:%w+_key$") then
      minetest.chat_send_player(name, "You must hold the paired key to use functions.")
      return true
    end
    local key_name = wielded:get_name()
    local is_owner = name == ent.owner

    -- Call dedicated funcs for each button (modular)
    if fields.toggle_lock then
      automobiles_lib.key_toggle_lock(ent, name)
      automobiles_lib.show_key_formspec(name, ent.car_id, key_name)
      return true
    elseif fields.panic and (key_name:find("fancy") or key_name:find("advanced")) then
      automobiles_lib.key_panic(ent)
      -- key_target_id[name] = nil
      return true
    elseif fields.locate and key_name:find("advanced") then
      automobiles_lib.key_locate(ent)
      -- key_target_id[name] = nil
      return true
    elseif fields.unpair and is_owner then
      automobiles_lib.key_unpair(player)
      key_target_id[name] = nil
      return true
    end
    -- No button pressed (e.g., ESC close) — timeout clears it
	
    return true
  end
end)

minetest.register_on_leaveplayer(function(player)
  local name = player:get_player_name()
  player_selected_bookmarks[name] = nil
end)

minetest.register_on_joinplayer(function(player)
  local name = player:get_player_name()
  player_selected_bookmarks[name] = nil
end)
