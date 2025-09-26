local S = delorean.S

-- Bookmark storage
local player_bookmarks = {}
local player_selected_bookmarks = {}  -- Track selected bookmarks per player

--------------
-- Manual --
--------------

function delorean.getCarFromPlayer(player)
    local seat = player:get_attach()
    if seat then
        local car = seat:get_attach()
        return car
    end
    return nil
end

-- Add bookmark function
function delorean.add_bookmark(player_name, name, pos)
    if not player_bookmarks[player_name] then
        player_bookmarks[player_name] = {}
    end
    
    -- Check if bookmark with this name already exists
    for i, bookmark in ipairs(player_bookmarks[player_name]) do
        if bookmark.name == name then
            -- Update existing bookmark
            player_bookmarks[player_name][i] = {name = name, pos = pos}
            return
        end
    end
    
    -- Add new bookmark
    table.insert(player_bookmarks[player_name], {name = name, pos = pos})
end

-- Remove bookmark function
function delorean.remove_bookmark(player_name, name)
    if not player_bookmarks[player_name] then return end
    
    for i, bookmark in ipairs(player_bookmarks[player_name]) do
        if bookmark.name == name then
            table.remove(player_bookmarks[player_name], i)
            -- Clear selection if we removed the selected bookmark
            if player_selected_bookmarks[player_name] and player_selected_bookmarks[player_name].name == name then
                player_selected_bookmarks[player_name] = nil
            end
            return
        end
    end
end

-- Get bookmark by name
function delorean.get_bookmark(player_name, name)
    if not player_bookmarks[player_name] then return nil end
    
    for _, bookmark in ipairs(player_bookmarks[player_name]) do
        if bookmark.name == name then
            return bookmark
        end
    end
    return nil
end

function delorean.driver_formspec(name)
    local player = minetest.get_player_by_name(name)
    local vehicle_obj = delorean.getCarFromPlayer(player)
    if vehicle_obj == nil then
        return
    end
    local ent = vehicle_obj:get_luaentity()

    local yaw = "false"
    if ent._yaw_by_mouse then yaw = "true" end
    
    local force_facing_dir = ent._force_facing_dir or false
    
    local flight = "false"
    if ent._is_flying == 1 then flight = "true" end
    
    local autodrive_state = "false"
    if ent._autodrive_active then autodrive_state = "true" end

    -- Build bookmark list and find selected index
    local bookmark_list = ""
    local selected_idx = 0
    local has_selection = false
    if player_bookmarks[name] then
        for i, bookmark in ipairs(player_bookmarks[name]) do
            bookmark_list = bookmark_list .. bookmark.name .. ","
            -- Check if this is the selected bookmark
            if player_selected_bookmarks[name] and player_selected_bookmarks[name].name == bookmark.name then
                selected_idx = i - 1  -- Textlist is 0-indexed
                has_selection = true
            end
        end
        -- Remove trailing comma
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
    local basic_form = table.concat({
        "formspec_version[3]",
        "size["..fs_width..",9]",
    }, "")

    -- Main controls (left side)
    basic_form = basic_form.."button[1,1.0;4,1;go_out;" .. S("Go Offboard") .. "]"
    basic_form = basic_form.."button[1,2.5;4,1;lights;" .. S("Lights") .. "]"
    if ent._car_type == 1 then 
      basic_form = basic_form.."checkbox[1,4.0;flight;" .. S("Flight Mode") .. ";"..flight.."]" 
    end
    basic_form = basic_form .. "checkbox[1,4.5;autodrive;" .. S("Autonomous Drive") .. ";" .. autodrive_state .. "]"
    basic_form = basic_form .. "checkbox[1,5.0;yaw;" .. S("Direction by Mouse") .. ";"..yaw.."]"
    basic_form = basic_form .. "checkbox[1,5.5;force_facing_dir;" .. S("Lock facing to car") .. ";".. tostring(force_facing_dir) .."]"
    
    -- Bookmark controls
    basic_form = basic_form.."field[1,6.5;3,1;bookmark_name;" .. S("Bookmark Name") .. ";]"
    basic_form = basic_form.."button[1,7.5;1.5,1;add_bookmark;" .. S("Add") .. "]"
    basic_form = basic_form.."button[2.5,7.5;1.5,1;remove_bookmark;" .. S("Del") .. "]"
    
    -- Bookmark list (sidebar)
    basic_form = basic_form.."label[6,0.5;" .. S("Bookmarks") .. "]"
    if bookmark_list ~= "" then
        if has_selection then
            basic_form = basic_form.."textlist[6,1;3.5,6;bookmark_list;" .. bookmark_list .. ";" .. tostring(selected_idx) .. "]"
        else
            basic_form = basic_form.."textlist[6,1;3.5,6;bookmark_list;" .. bookmark_list .. ";0]"
        end
    else
        basic_form = basic_form.."textlist[6,1;3.5,6;bookmark_list;;0]"
    end
    basic_form = basic_form.."button[6,7.2;3.5,0.8;goto_bookmark;" .. S("Set Target") .. "]"
    basic_form = basic_form..fs_radio
    minetest.show_formspec(name, "delorean:driver_main", basic_form)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname == "delorean:driver_main" then
        local name = player:get_player_name()
        local car_obj = delorean.getCarFromPlayer(player)
        if car_obj then
            local ent = car_obj:get_luaentity()
            if ent then
                if fields.go_out then
                    if ent._passenger then --any pax?
                        local pax_obj = minetest.get_player_by_name(ent._passenger)
                        automobiles_lib.dettach_pax(ent, pax_obj)
                    end
                    ent._is_flying = 0
                    minetest.close_formspec(name, "delorean:driver_main")
                    automobiles_lib.dettach_driver(ent, player)
                    return  -- Exit early for go_out
                end
                if fields.lights then
                    if ent._show_lights == true then
                        ent._show_lights = false
                        ent._show_running_lights = false
                    else
                        ent._show_lights = true
                        ent._show_running_lights = true
                    end
                    minetest.close_formspec(name, "delorean:driver_main")
                end
                if fields.yaw then
                    if ent._yaw_by_mouse == true then
                        ent._yaw_by_mouse = false
                    else
                        ent._yaw_by_mouse = true
                    end
                    minetest.close_formspec(name, "delorean:driver_main")
                end
                if fields.force_facing_dir then
                    if ent._force_facing_dir == true then
                        ent._force_facing_dir = false
                    else
                        ent._force_facing_dir = true
                        ent._yaw_by_mouse = false
                    end
                    minetest.close_formspec(name, "delorean:driver_main")
                end
                if fields.flight then
                    if ent._is_flying == 1 then
                        ent._is_flying = 0
                    else
                        ent._is_flying = 1
                    end
                    delorean.turn_flight_mode(ent)
                    minetest.close_formspec(name, "delorean:driver_main")
                end
                if fields.autodrive then
                    if ent._autodrive_active then
                        -- Deactivate autodrive
                        ent._autodrive_active = false
                        if autodrive then
                            autodrive.deactivate(ent)
                        end
                    else
                        -- Activate autodrive - if target is set, start navigation
                        if autodrive and player_selected_bookmarks[name] then
                            autodrive.set_target(ent, player_selected_bookmarks[name].pos)
                            minetest.chat_send_player(name, S("Navigating to bookmark '@1' at @2", 
                                player_selected_bookmarks[name].name, 
                                minetest.pos_to_string(player_selected_bookmarks[name].pos)))
                        end
                        ent._autodrive_active = true
                        if autodrive then
                            autodrive.activate(ent)
                        end
                    end
                    -- Refresh formspec to show updated checkbox state
                    delorean.driver_formspec(name)
                    return
                end
                
                -- Bookmark management
                if fields.add_bookmark and fields.bookmark_name and fields.bookmark_name ~= "" then
                    local pos = ent.object:get_pos()
                    delorean.add_bookmark(name, fields.bookmark_name, pos)
                    minetest.chat_send_player(name, S("Bookmark '@1' added at @2", fields.bookmark_name, minetest.pos_to_string(pos)))
                    delorean.driver_formspec(name)  -- Refresh to show new bookmark
                    return
                end
                
                if fields.remove_bookmark and fields.bookmark_name and fields.bookmark_name ~= "" then
                    delorean.remove_bookmark(name, fields.bookmark_name)
                    minetest.chat_send_player(name, S("Bookmark '@1' removed", fields.bookmark_name))
                    delorean.driver_formspec(name)  -- Refresh to show updated list
                    return
                end
                
                -- Handle bookmark selection - Fixed the selection logic
                if fields.bookmark_list then
                    local list_event = fields.bookmark_list
                    if string.find(list_event, "CHG:") then
                        -- Get the index from the CHG event
                        local index_str = string.match(list_event, "CHG:(%d+)")
                        if index_str then
                            local selected_index = tonumber(index_str)
                            if selected_index and player_bookmarks[name] then
                                -- Convert to 1-indexed for Lua table access
                                local actual_index = selected_index + 1
                                if player_bookmarks[name][actual_index] then
                                    player_selected_bookmarks[name] = player_bookmarks[name][actual_index]
                                    -- minetest.chat_send_player(name, S("Selected bookmark '@1'", player_selected_bookmarks[name].name))
                                end
                            end
                        end
                        delorean.driver_formspec(name)  -- Refresh to show selection
                        return
                    end
                end
                
                -- Set target (but don't activate autodrive)
                if fields.goto_bookmark then
                    if player_selected_bookmarks[name] then
                        local bookmark = player_selected_bookmarks[name]
                        -- Set target for autodrive system
                        if autodrive then
                            autodrive.set_target(ent, bookmark.pos)
                            minetest.chat_send_player(name, S("Target set to bookmark '@1' at @2", 
                                bookmark.name, minetest.pos_to_string(bookmark.pos)))
                        end
                    else
                        minetest.chat_send_player(name, S("Please select a bookmark first"))
                    end
                    delorean.driver_formspec(name)  -- Refresh formspec
                    return
                end
                if automobiles_lib.handle_radio_formspec_fields then
                  automobiles_lib.handle_radio_formspec_fields(name, ent, fields)
                end
            end
        end
        -- Don't close formspec for any action - let player close it manually
    end
end)

-- Clear selection when player leaves
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    player_selected_bookmarks[name] = nil
end)

-- Initialize selection tracking on join
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    player_selected_bookmarks[name] = nil
end)