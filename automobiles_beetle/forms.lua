local S = auto_beetle.S

function auto_beetle.driver_formspec(name)
    local player = minetest.get_player_by_name(name)
    local vehicle_obj = automobiles_lib.getCarFromPlayer(player)
    if vehicle_obj == nil then
        return
    end
    local ent = vehicle_obj:get_luaentity()

    local yaw = "false"
    if ent._yaw_by_mouse then yaw = "true" end
    local force_facing_dir = ent._force_facing_dir or false

  local fs_width = 6
  local fs_radio = ""
  if automobiles_lib.get_radio_formspec_fragment then
    fs_radio = automobiles_lib.get_radio_formspec_fragment(ent,fs_width)
    fs_width = fs_width + 4
  end
  local basic_form = table.concat({
        "formspec_version[3]",
        "size["..fs_width..",8]",
	}, "")
	basic_form = basic_form.."button[1,1.0;4,1;go_out;" .. S("Go Offboard") .. "]"
	basic_form = basic_form.."button[1,2.5;4,1;top;" .. S("Close/Open Ragtop") .. "]"
  basic_form = basic_form.."button[1,4.0;4,1;lights;" .. S("Lights") .. "]"
  basic_form = basic_form.."checkbox[1,5.5;yaw;" .. S("Direction by mouse") .. ";"..yaw.."]"
  basic_form = basic_form .. "checkbox[1,6.0;force_facing_dir;" .. S("Lock facing to car") .. ";".. tostring(force_facing_dir) .."]"
  basic_form = basic_form .. fs_radio
  minetest.show_formspec(name, "auto_beetle:driver_main", basic_form)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname == "auto_beetle:driver_main" then
        local name = player:get_player_name()
        local car_obj = automobiles_lib.getCarFromPlayer(player)
        if car_obj then
            local ent = car_obj:get_luaentity()
            if ent then
                if fields.top then
                    if ent._show_rag == true then
                        ent._show_rag = false
                    else
                        ent._show_rag = true
                    end
                end
		        if fields.go_out then

                    if ent._passenger then --any pax?
                        local pax_obj = minetest.get_player_by_name(ent._passenger)
                        automobiles_lib.dettach_pax(ent, pax_obj)
                    end

                    automobiles_lib.dettach_driver(ent, player)
		        end
                if fields.lights then
                    if ent._show_lights == true then
                        ent._show_lights = false
                        ent._show_running_lights = false
                    else
                        ent._show_lights = true
                        ent._show_running_lights = true
                    end
                end
                if fields.yaw then
                    if ent._yaw_by_mouse == true then
                        ent._yaw_by_mouse = false
                    else
                        ent._yaw_by_mouse = true
                    end
                end
                if fields.force_facing_dir then
                    if ent._force_facing_dir == true then
                        ent._force_facing_dir = false
                    else
                        ent._force_facing_dir = true
                        ent._yaw_by_mouse = false
                    end
                    minetest.close_formspec(name, "auto_beetle:driver_main")
                end
                if automobiles_lib.handle_radio_formspec_fields then
                  automobiles_lib.handle_radio_formspec_fields(name, ent, fields)
                end
            end
        end
        minetest.close_formspec(name, "auto_beetle:driver_main")
    end
end)
