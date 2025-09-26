-- Globals for key system and car registry
key_target_car = key_target_car or {}
car_registry = car_registry or {}  -- NEW: [car_id] = luaentity (for reliable lookup)

local S = automobiles_lib.S  -- Define early for use in functions below
local MAX_ACCEL = 25
local ACC_ADJUST = 10
local ENERGY_CONSUMPTION_BASE = 40000

minetest.register_entity('automobiles_lib:pivot_mesh', {
  initial_properties = {
    physical = false,
    collide_with_objects = false,
    pointable = false,
    visual = "mesh",
    mesh = "automobiles_pivot_mesh.b3d",
    textures = { "automobiles_alpha.png", },
  },

  on_activate = function(self, std)
    self.sdata = minetest.deserialize(std) or {}
    if self.sdata.remove then self.object:remove() end
  end,

  get_staticdata = function(self)
    self.sdata.remove = true
    return minetest.serialize(self.sdata)
  end,
})

minetest.register_entity("automobiles_lib:license_plate", {
    collisionbox = { 0, 0, 0, 0, 0, 0 },
    visual = "upright_sprite",
    textures = {},
    on_activate = function(self)
        local meta = minetest.get_meta(self.object:get_pos())
        local text = meta:get_string("plate_text") or "UNKNOWN"
        self.object:set_properties({
            textures = {
                generate_texture(create_lines(text))  -- Reuse Digilines LCD logic
            }
        })
    end,
})

minetest.register_entity('automobiles_lib:pointer', {
  initial_properties = {
    physical = false,
    collide_with_objects = false,
    pointable = false,
    visual = "mesh",
    mesh = "automobiles_pointer.b3d",
    visual_size = { x = 0.5, y = 0.5, z = 0.5 },
    textures = { "automobiles_white.png" },
  },

  on_activate = function(self, std)
    self.sdata = minetest.deserialize(std) or {}
    if self.sdata.remove then self.object:remove() end
  end,

  get_staticdata = function(self)
    self.sdata.remove = true
    return minetest.serialize(self.sdata)
  end,
})

-- NEW: Helper to get car entity by unique ID (from registry)
function automobiles_lib.get_car_by_id(car_id)
  if not car_registry[car_id] then
    smartlog("singleplayer", "DEBUG: Car ID '" .. tostring(car_id) .. "' not found in registry.")  -- Debug line; remove or adjust as needed
    return nil
  end
  local ent = car_registry[car_id]
  if ent and ent.object and ent.owner and ent.owner ~= "" then
    smartlog("singleplayer", "DEBUG: Car ID '" .. tostring(car_id) .. "' found, owner: '" .. tostring(ent.owner) .. "'.")  -- Debug line; remove or adjust as needed
    return ent
  end
  -- Invalidate if stale
  smartlog("singleplayer", "DEBUG: Car ID '" .. tostring(car_id) .. "' stale, removing from registry.")  -- Debug line; remove or adjust as needed
  car_registry[car_id] = nil
  return nil
end

function automobiles_lib.on_rightclick(self, clicker)
  if not clicker or not clicker:is_player() then
    return
  end
  
  local name = clicker:get_player_name()
  
  -- Enhanced Lock Check with Debug (remove prints later)
  local lock_debug = S("DEBUG: Car locked? @1, Owner? @2, You are owner? @3", tostring(self._locked), self.owner or "nil", tostring(name == self.owner))
  smartlog(name, lock_debug)
  minetest.log("action", "Rightclick on car: Player=" .. name .. ", Locked=" .. tostring(self._locked) .. ", Owner=" .. (self.owner or "nil"))

  -- Block entry if locked (unless owner or has authorized key)
  if self._locked then
    if name ~= self.owner then
      local has_key = automobiles_lib.has_authorized_key(clicker, self.owner)
      smartlog(name, S("DEBUG: Has key? @1", tostring(has_key)))
      if not has_key then
        smartlog(name, S("Car is locked. Use a key to unlock first."))
        minetest.log("action", "Blocked entry for " .. name .. " on locked car of " .. self.owner .. " (no key)")
        return
      else
        smartlog(name, S("Entry allowed: Authorized key found!"))
        minetest.log("action", "Allowed entry for " .. name .. " on locked car of " .. self.owner .. " (has key)")
      end
    else
      smartlog(name, S("Entry allowed: You are the owner!"))
      minetest.log("action", "Allowed entry for owner " .. name .. " on locked car")
    end
  else
    smartlog(name, S("Entry allowed: Car is unlocked."))
    minetest.log("action", "Allowed entry for " .. name .. " on unlocked car")
  end

  -- Owner Setup (if new car)
  if self.owner == "" then
    self.owner = name
    if not self.car_id then  -- Generate ID if not set
      self.car_id = generate_car_id(name)
      car_registry[self.car_id] = self
      smartlog(name, S("DEBUG: Set as owner & generated car ID '@1'.", self.car_id))
    end
  end

  -- Original Rightclick Logic (unchanged: driver formspec, attachment, etc.)
  if name == self.driver_name then
    local formspec_f = automobiles_lib.driver_formspec
    if self._formspec_function then formspec_f = self._formspec_function end
    formspec_f(name)
  else
    if ( automobiles_lib.has_authorized_key(clicker, self.owner) or
          false or clicker:get_player_name() == self.owner ) and (self.driver_name == nil) then
        
      --why is it different then when your in the car huhhhhhhhh
      if clicker:get_player_control().sneak then
        automobiles_lib.show_vehicle_trunk_formspec(self, clicker, self._trunk_slots)
      else
        -- Attach as driver
        local attach_driver_f = automobiles_lib.attach_driver
        if self._attach then attach_driver_f = self._attach end
        self._show_lights = self._show_running_lights or false
        attach_driver_f(self, clicker)
        -- Engine sound
        local engine_sound_wait = 0
        local base_pitch = self._base_pitch or 1
        if self._engine_startup_sound then
        minetest.sound_play({ name = self._engine_startup_sound },
          { object = self.object, gain = 1, pitch = base_pitch, max_hear_distance = 15, loop = false, })
          engine_sound_wait = self._engine_delay or 0.5
        else
          engine_sound_wait = 0
        end
        minetest.after(engine_sound_wait, function()
          self.sound_handle = minetest.sound_play({ name = self._engine_sound },
            { object = self.object, gain = 1, pitch = base_pitch, max_hear_distance = 15, loop = true, })
        end)
        -- self._engine_first_action=true
      end
      
    else
      -- Passenger logic
      if (automobiles_lib.is_minetest and not player_api.player_attached[name]) or
          (automobiles_lib.is_mcl and not mcl_player.player_attached[name]) then
        if self.driver_name or (not self._locked and not automobiles_lib.has_authorized_key(clicker, self.owner)) then
          local attach_pax_f = automobiles_lib.attach_pax
          if self._attach_pax then attach_pax_f = self._attach_pax end
          attach_pax_f(self, clicker, true)
        end
      else
        local dettach_pax_f = automobiles_lib.dettach_pax
        if self._dettach_pax then dettach_pax_f = self._dettach_pax end
        dettach_pax_f(self, clicker)
      end
    end
  end
end

function automobiles_lib.on_punch(self, puncher, ttime, toolcaps, dir, damage)
  local S = automobiles_lib.S  -- FIXED: Define S here to avoid nil errors

  -- Wrap in pcall for error handling (logs issues without crashing)
  local success, err = pcall(function()
    if not puncher or not puncher:is_player() then
      minetest.log("action", "Punch: Ignored (not a player)")
      return
    end

    local name = puncher:get_player_name()
    minetest.log("action", "Punch: By player '" .. name .. "' on entity '" .. (self.object and self.object:get_luaentity().name or "unknown") .. "'")
    smartlog(name, "DEBUG: Punch detected by " .. name)

    --[[if self.owner and self.owner ~= name and self.owner ~= "" then return end]]   --
    if self.owner == nil then
      self.owner = name
      smartlog(name, "DEBUG: Set as owner (was nil)")
    end
    smartlog(name, "DEBUG: Current owner is '" .. (self.owner or "nil") .. "'")

    if not minetest.check_player_privs(puncher, { server = true }) and (self.owner and self.owner ~= name) then
      smartlog(name, "DEBUG: Blocked (driver is '" .. self.owner .. "')")
      -- minetest.chat_send_all(tostring(minetest.check_player_privs(puncher, { server = true })
      -- do not allow other players to remove the object while there is a driver
      return
    end

    local is_attached = false
    local obj_attach = puncher:get_attach()
    if obj_attach == self.driver_seat or obj_attach == self.object then is_attached = true end
    if is_attached then
      smartlog(name, "DEBUG: Blocked (you are attached)")
      return
    end

    local itmstck = puncher:get_wielded_item()
    local item_name = itmstck and itmstck:get_name() or ""
    smartlog(name, "DEBUG: Wielded item: '" .. item_name .. "'")

    smartlog(name, "DEBUG: Car owner is '" .. (self.owner or "nil") .. "'")

    -- Test the match pattern manually for debug
    local key_match = item_name:match("^automobiles_lib:%w+_key$")  -- Exact match for basic_key, fancy_key, advanced_key
    smartlog(name, "DEBUG: Item '" .. item_name .. "' matches key pattern? " .. tostring(key_match ~= nil))

    -- New: Key System Handling on Punch (Left-Click)
    if key_match then  -- Use the tested match
      smartlog(name, "DEBUG: Key match detected! (using exact pattern)")
      local meta = itmstck:get_meta()
      local paired_owner = meta:get("paired_owner") or ""
      local paired_id = meta:get("paired_id") or ""  -- NEW: Check paired car ID
      smartlog(name, "DEBUG: Paired owner in meta: '" .. paired_owner .. "' | Car owner: '" .. (self.owner or "nil") .. "' | Paired ID: '" .. paired_id .. "'")
      
      if paired_owner == "" then
        smartlog(name, "DEBUG: Unpaired key detected - checking owner...")
        -- Unpaired: Attempt to pair (owner only)
        if name == self.owner or minetest.check_player_privs(clicker, { server = true }) then
          smartlog(name, "DEBUG: Pairing key... (owner confirmed)")
          meta:set_string("paired_owner", self.owner)
          meta:set_string("paired_id", self.car_id or "")  -- NEW: Store car ID in key meta
          meta:set_string("car_color", self._color or "#FFFFFF")
          meta:set_string("key_type", item_name)  -- Store full name for type check
          local key_type = item_name:gsub("automobiles_lib:", "")
          -- FIXED: Use @1/@2/@3 for Minetest S formatting
          local new_desc = S("Paired @1 Key for @2 (ID: @3)", key_type, self.owner, self.car_id or "unknown")
          meta:set_string("description", new_desc)
          -- FIXED: No set_meta needed
          puncher:set_wielded_item(itmstck)  -- This applies all meta changes
          minetest.chat_send_player(name, S("Key paired to your car (ID: @1)! Punch again to use functions.", self.car_id or "unknown"))
          return
        else
          minetest.chat_send_player(name, S("Only the car owner (@1) can pair keys.", self.owner or "unknown"))
          return
        end
      elseif paired_owner == self.owner and (paired_id == "" or paired_id == self.car_id) then
        smartlog(name, "DEBUG: Paired key matches car - opening formspec...")
        -- Paired and matches: Open the key formspec (store ID instead of entity)
        if automobiles_lib.show_key_formspec then
          automobiles_lib.show_key_formspec(name, self.car_id, item_name)  -- NEW: Pass ID instead of self
        else
          minetest.chat_send_player(name, "ERROR: show_key_formspec function missing! Check formspecs.lua or entities.lua load order.")
        end
        return
      else
        -- Paired but to wrong car/owner/ID
        minetest.chat_send_player(name, S("This key is already paired to another car (@1 ID: @2). Unpair first.", paired_owner, paired_id))
        return
      end
    else
      smartlog(name, "DEBUG: Not a key (continuing to normal punch logic)")
    end

    -- Define longit_speed_drag if not already (from control logic; minor fix)
    local longit_speed_drag = 0  -- Placeholder; actual from control() if needed

    --refuel procedure
    --[[
      refuel works it car is stopped and engine is off
      ]] --
    local velocity = self.object:get_velocity()
    local speed = automobiles_lib.get_hipotenuse_value(vector.new(), velocity)
    --if math.abs(speed) <= 0.1 then
    local was_refueled = automobiles_lib.loadFuel(self, puncher:get_player_name(), false, self._max_fuel)
    if was_refueled then
      smartlog(name, "DEBUG: Refueled")
      return
    end
    --end
    -- end refuel

    if is_attached == false then
      smartlog(name, "DEBUG: Handling paint/destroy (not attached)")
     -- deal with painting or destroying
      if itmstck then
        --race status restart
        if item_name == "checkpoints:status_restarter" and self._engine_running == false then
          --restart race current status
          self._last_checkpoint = ""
          self._total_laps = -1
          self._race_id = ""
          return
        end

        local paint_f = automobiles_lib.set_paint
        if self._painting_function then paint_f = self._painting_function end
        if paint_f(self, puncher, itmstck) == false then
          local is_admin = false
          is_admin = minetest.check_player_privs(puncher, { server = true })
          --minetest.chat_send_all('owner '.. self.owner ..' - name '.. name)
          if not self.driver and (self.owner == name or is_admin == true) and toolcaps and
              toolcaps.damage_groups and toolcaps.damage_groups.fleshy then
            if self.sound_handle then minetest.sound_stop(self.sound_handle) end
            self.hp = self.hp - 10
            minetest.sound_play("automobiles_collision", {
              object = self.object,
              max_hear_distance = 5,
              gain = 1.0,
              fade = 0.0,
              pitch = 1.0,
            })
          end
        end
      end

      if self.hp <= 0 then
        local destroy_f = automobiles_lib.destroy
        if self._destroy_function then destroy_f = self._destroy_function end
        destroy_f(self)
        [[minetest.after(self._engine_delay or 0.5,function()
          minetest.sound_stop(self.sound_handle)
        end)]]
        
        smartlog(name, "DEBUG: Destroyed car")
      end
    end
  end)  -- End pcall function

  if not success then
    -- minetest.log("error", "on_punch error for " .. (puncher:get_player_name() or "unknown") .. ": " .. tostring(err))
    if puncher and puncher:is_player() then
      smartlog(puncher:get_player_name(), "Error in punch handling: Try dropping your key and picking it up")
    end
  end
end

function automobiles_lib.get_staticdata(self)
  return minetest.serialize({
    stored_owner = self.owner,
    stored_hp = self.hp,
    stored_color = self._color,
    stored_det_color = self._det_color,
    stored_locked = self._locked,  -- Locked state
    stored_car_id = self.car_id,  -- NEW: Persist unique car ID
    stored_steering = self._steering_angle,
    stored_energy = self._energy,
    stored_rag = self._show_rag,
    stored_running_lights = self._show_running_lights,
    stored_yaw_by_mouse = self._yaw_by_mouse,
    stored_locked = self._locked,
    stored_force_facing_dir = self._force_facing_dir,
    stored_pitch = self._pitch,
    stored_light_old_pos = self._light_old_pos,
    stored_inv_id = self._inv_id,
    stored_car_type = self._car_type,
    stored_car_gravity = self._car_gravity,
    stored_scale = self._vehicle_scale or 1,
    stored_power_scale = self._vehicle_power_scale or 1,
    --race data
    stored_last_checkpoint = self._last_checkpoint,
    stored_total_laps = self._total_laps,
    stored_race_id = self._race_id,
  })
end

-- NEW: On deactivate handler to unregister from registry (call from entity defs)
function automobiles_lib.on_deactivate(self)
  if self.car_id and car_registry[self.car_id] then
    car_registry[self.car_id] = nil
  end
  automobiles_lib.save_inventory(self)  -- Your original
end

local function scale_entity(self, scale)
  scale = scale or 1
  local initial_properties = automobiles_lib.properties_copy(self.initial_properties)
  local new_properties = automobiles_lib.properties_copy(initial_properties)

  --[[if initial_properties.collisionbox then
		for i, value in ipairs(initial_properties.collisionbox) do
			new_properties.collisionbox[i] = value * scale
            --core.log("action", new_properties.collisionbox[i])
		end
	end

	if initial_properties.selectionbox then
		for i, value in ipairs(initial_properties.selectionbox) do
			new_properties.selectionbox[i] = value * scale
		end
	end]] --

  if initial_properties.stepheight then
    new_properties.stepheight = initial_properties.stepheight * scale
  end

  new_properties.visual_size = { x = scale, y = scale }

  self.object:set_properties(new_properties)
end

function automobiles_lib.on_activate(self, staticdata, dtime_s)
  if staticdata ~= "" and staticdata ~= nil then
    local data = minetest.deserialize(staticdata) or {}
    self.owner = data.stored_owner
    self.hp = data.stored_hp
    self._color = data.stored_color
    self._det_color = data.stored_det_color
    self._locked = data.stored_locked or false  -- FIXED: Deserialize locked state
    self.car_id = data.stored_car_id or generate_car_id(self.owner or "unknown")  -- NEW: Load or generate ID
    self._autodrive_active = false
    self._steering_angle = data.stored_steering
    self._energy = data.stored_energy
    self._yaw_by_mouse = data.stored_yaw_by_mouse or false
    self._show_running_lights = data.stored_running_lights or false
    self._locked = data.stored_locked or false
    self._force_facing_dir = data.stored_force_facing_dir or false
    --minetest.debug("loaded: ", self.energy)
    --race data
    self._last_checkpoint = data.stored_last_checkpoint
    self._total_laps = data.stored_total_laps
    self._race_id = data.stored_race_id
    self._show_rag = data.stored_rag
    self._pitch = data.stored_pitch
    self._light_old_pos = data.stored_light_old_pos
    self._inv_id = data.stored_inv_id

    self._car_type = data.stored_car_type
    self._car_gravity = data.stored_car_gravity or -automobiles_lib.gravity
    self._vehicle_scale = data.stored_scale or 1
    self._vehicle_power_scale = data.stored_power_scale or 1

    automobiles_lib.setText(self, self._vehicle_name)
    if data.remove then
      automobiles_lib.destroy_inventory(self)
      self.object:remove()
      return
    end
  else
    -- New entity: Generate ID based on owner (set after)
    self.car_id = nil  -- Will set after owner confirmation in on_punch/rightclick
  end

  self._locked = self._locked or false  -- Default if new entity

  scale_entity(self, self._vehicle_scale)

  if self._painting_load then
    self._painting_load(self, self._color)
  else
    automobiles_lib.paint(self, self._color)
  end

  local pos = self.object:get_pos()

  local front_suspension = minetest.add_entity(self.object:get_pos(), self._front_suspension_ent)
  front_suspension:set_attach(self.object, '', self._front_suspension_pos, { x = 0, y = 0, z = 0 })
  self.front_suspension = front_suspension

  if self._front_wheel_ent then
    local lf_wheel = minetest.add_entity(pos, self._front_wheel_ent)
    lf_wheel:set_attach(self.front_suspension, '', { x = -self._front_wheel_xpos, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    -- set the animation once and later only change the speed
    lf_wheel:set_animation(self._front_wheel_frames, 0, 0, true)
    self.lf_wheel = lf_wheel

    local rf_wheel = minetest.add_entity(pos, self._front_wheel_ent)
    rf_wheel:set_attach(self.front_suspension, '', { x = self._front_wheel_xpos, y = 0, z = 0 }, { x = 0, y = 180, z = 0 })
    -- set the animation once and later only change the speed
    rf_wheel:set_animation(self._front_wheel_frames, 0, 0, true)
    self.rf_wheel = rf_wheel
  end

  local rear_suspension = minetest.add_entity(self.object:get_pos(), self._rear_suspension_ent)
  rear_suspension:set_attach(self.object, '', self._rear_suspension_pos, { x = 0, y = 0, z = 0 })
  self.rear_suspension = rear_suspension

  if self._rear_wheel_ent then
    local lr_wheel = minetest.add_entity(pos, self._rear_wheel_ent)
    lr_wheel:set_attach(self.rear_suspension, '', { x = -self._rear_wheel_xpos, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    -- set the animation once and later only change the speed
    lr_wheel:set_animation(self._rear_wheel_frames, 0, 0, true)
    self.lr_wheel = lr_wheel

    local rr_wheel = minetest.add_entity(pos, self._rear_wheel_ent)
    rr_wheel:set_attach(self.rear_suspension, '', { x = self._rear_wheel_xpos, y = 0, z = 0 }, { x = 0, y = 180, z = 0 })
    -- set the animation once and later only change the speed
    rr_wheel:set_animation(self._rear_wheel_frames, 0, 0, true)
    self.rr_wheel = rr_wheel
  end


  if self._steering_ent then
    local steering_axis = minetest.add_entity(pos, 'automobiles_lib:pivot_mesh')
    steering_axis:set_attach(self.object, '', self._drive_wheel_pos, { x = self._drive_wheel_angle, y = 0, z = 0 })
    self.steering_axis = steering_axis

    local steering = minetest.add_entity(self.steering_axis:get_pos(), self._steering_ent)
    steering:set_attach(self.steering_axis, '', { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    self.steering = steering
  end

  if self._rag_retracted_ent then
    local rag_rect = minetest.add_entity(self.object:get_pos(), self._rag_retracted_ent)
    rag_rect:set_attach(self.object, '', { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    self.rag_rect = rag_rect
    self.rag_rect:set_properties({ is_visible = false })
  end

  if self._rag_extended_ent then
    local rag = minetest.add_entity(self.object:get_pos(), self._rag_extended_ent)
    rag:set_attach(self.object, '', { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    self.rag = rag
  end

  automobiles_lib.seats_create(self)

  local pointer_entity = 'automobiles_lib:pointer'
  if self._gauge_pointer_ent then pointer_entity = self._gauge_pointer_ent end
  if self._fuel_gauge_pos then
    local fuel_gauge = minetest.add_entity(pos, pointer_entity)
    fuel_gauge:set_attach(self.object, '', self._fuel_gauge_pos, { x = 0, y = 0, z = 0 })
    self.fuel_gauge = fuel_gauge
  end

  if self._front_lights then
    local lights = minetest.add_entity(pos, self._front_lights)
    lights:set_attach(self.object, '', { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    self.lights = lights
    self.lights:set_properties({ is_visible = true })
  end

  if self._rear_lights then
    local r_lights = minetest.add_entity(pos, self._rear_lights)
    r_lights:set_attach(self.object, '', { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    self.r_lights = r_lights
    self.r_lights:set_properties({ is_visible = true })
  end

  if self._reverse_lights then
    local reverse_lights = minetest.add_entity(pos, self._reverse_lights)
    reverse_lights:set_attach(self.object, '', { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    self.reverse_lights = reverse_lights
    self.reverse_lights:set_properties({ is_visible = true })
  end

  if self._turn_left_lights then
    local turn_l_light = minetest.add_entity(pos, self._turn_left_lights)
    turn_l_light:set_attach(self.object, '', { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    self.turn_l_light = turn_l_light
    self.turn_l_light:set_properties({ is_visible = true })
  end

  if self._turn_right_lights then
    local turn_r_light = minetest.add_entity(pos, self._turn_right_lights)
    turn_r_light:set_attach(self.object, '', { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    self.turn_r_light = turn_r_light
    self.turn_r_light:set_properties({ is_visible = true })
  end
  
  -- Recreate license plate entity
  -- if self.car_id then
    -- local plate = minetest.add_entity(self.object:get_pos(), "automobiles_lib:license_plate")
    -- plate:set_attach(self.object, '', { x = 0, y = 0.3, z = -20 }, { x = 0, y = 180, z = 0 })
    -- local meta = minetest.get_meta(plate:get_pos())
    -- meta:set_string("plate_text", self.car_id)
    -- self.license_plate = plate
  -- end


  if self._extra_items_function then
    self._extra_items_function(self)
  end

  self.object:set_armor_groups({ immortal = 1 })

  local inv = minetest.get_inventory({ type = "detached", name = self._inv_id })
  -- if the game was closed the inventories have to be made anew, instead of just reattached
  if not inv then
    automobiles_lib.create_inventory(self, self._trunk_slots)
  else
    self.inv = inv
  end

  -- NEW: Register this car in the global registry by ID
  if self.car_id then
    car_registry[self.car_id] = self
    minetest.log("action", "Registered car ID '" .. self.car_id .. "' for owner '" .. (self.owner or "unknown") .. "'")
  end
  if automobiles_lib.scan_radio_tracks then
    self.radio_tracks = automobiles_lib.scan_radio_tracks("automobiles_radio", "sounds")
  end
  automobiles_lib.actfunc(self, staticdata, dtime_s)
end

-- NEW: Add on_deactivate to entity registrations (e.g., in Delorean: on_deactivate = automobiles_lib.on_deactivate)
-- This unregisters the car ID when entity unloads

function automobiles_lib.on_step(self, dtime)
  automobiles_lib.stepfunc(self, dtime)

  --[[sound play control]]   --
  self._last_time_collision_snd = self._last_time_collision_snd + dtime
  if self._last_time_collision_snd > 1 then self._last_time_collision_snd = 1 end
  self._last_time_drift_snd = self._last_time_drift_snd + dtime
  if self._last_time_drift_snd > 2.0 then self._last_time_drift_snd = 2.0 end
  --[[end sound control]]   --

  --in case it's not declared
  self._max_acc_factor = self._max_acc_factor or 1
  self._vehicle_scale = self._vehicle_scale or 1
  self._vehicle_power_scale = self._vehicle_power_scale or self._vehicle_scale
  self.key_flash = self.key_flash or 0
  self._key_flash_active = self._key_flash_active or false
  self._key_flash_timer = self._key_flash_timer or 0
  self._key_flash_count = self._key_flash_count or 0
  self._key_flash_on = self._key_flash_on or false

  local rotation = self.object:get_rotation()
  local yaw = rotation.y
  local newyaw = yaw
  local pitch = rotation.x
  local roll = rotation.z

  local hull_direction = minetest.yaw_to_dir(yaw)
  local nhdir = { x = hull_direction.z, y = 0, z = -hull_direction.x } -- lateral unit vector
  local velocity = self.object:get_velocity()

  local longit_speed = automobiles_lib.dot(velocity, hull_direction)
  local fuel_weight_factor = (5 - self._energy) / 5000
  local longit_drag = vector.multiply(hull_direction, (longit_speed * longit_speed) *
    (self._LONGIT_DRAG_FACTOR - fuel_weight_factor) * -1 * automobiles_lib.sign(longit_speed))

  local later_speed = automobiles_lib.dot(velocity, nhdir)
  local dynamic_later_drag = self._LATER_DRAG_FACTOR
  if longit_speed > 2 then dynamic_later_drag = 2.0 end
  if longit_speed > 8 then dynamic_later_drag = 0.5 end
  --core.chat_send_all(dump(longit_speed))

  if automobiles_lib.extra_drift and longit_speed > (4 * self._vehicle_power_scale) then
    dynamic_later_drag = dynamic_later_drag / (longit_speed * 2)
  end

  local later_drag = vector.new()
  if self._is_motorcycle == true then
    later_drag = vector.multiply(nhdir, later_speed *
      later_speed * self._LATER_DRAG_FACTOR * -1 * automobiles_lib.sign(later_speed))
  else
    later_drag = vector.multiply(nhdir, later_speed *
      later_speed * dynamic_later_drag * -1 * automobiles_lib.sign(later_speed))
  end

  local accel = vector.add(longit_drag, later_drag)
  local stop = nil
  local curr_pos = self.object:get_pos()

  if self._show_rag == true then
    if self._windshield_pos and self._windshield_ext_rotation then
      self.object:set_bone_position("windshield", self._windshield_pos, self._windshield_ext_rotation)       --extended
    end
    if self.rag_rect then self.rag_rect:set_properties({ is_visible = true }) end
    if self.rag then self.rag:set_properties({ is_visible = false }) end
  else
    if self._windshield_pos then
      self.object:set_bone_position("windshield", self._windshield_pos, { x = 0, y = 0, z = 0 }) --retracted
    end
    if self.rag_rect then self.rag_rect:set_properties({ is_visible = false }) end
    if self.rag then self.rag:set_properties({ is_visible = true }) end
  end

  if self.driver_name and self._force_facing_dir then
    local player = minetest.get_player_by_name(self.driver_name)
    player:set_look_horizontal(yaw)
    player:set_look_vertical(pitch)
  end
  
  local player = nil
  local is_attached = false
  if self.driver_name then
    player = minetest.get_player_by_name(self.driver_name)

    if player then
      local player_attach = player:get_attach()
      if player_attach then
        if self.driver_seat then
          if player_attach == self.driver_seat or player_attach == self.object then is_attached = true end
        end
      end
    end
  end

  -- Handle flying mode
  if self._setmode then
    self._setmode(self, is_attached, curr_pos, velocity, player, dtime)
  end

  -- Handle player controls
  local is_braking = false
  if is_attached then
    local ctrl = player:get_player_control()

    if ctrl.jump then
      dynamic_later_drag = 0.2
    end

    if ctrl.aux1 and self._last_time_command > 0.8 then
      self._last_time_command = 0
      local horn_sound = self._horn_sound or "automobiles_horn"
      minetest.sound_play(horn_sound, {
        object = self.object,
        gain = 0.6,
        pitch = 1.0,
        max_hear_distance = 32,
        loop = false,
      })
    end

    if ctrl.down then
      is_braking = true
      if self.r_lights then
        self.r_lights:set_properties({ textures = { "automobiles_rear_lights_full.png" }, glow = 15 })
      end
    end

    if self.reverse_lights then
      self.reverse_lights:set_properties({ textures = { ctrl.sneak and "automobiles_white.png" or "automobiles_grey.png" }, glow = ctrl.sneak and 15 or 0 })
    end
  end

  -- Handle light updates
  self._last_light_move = self._last_light_move + dtime
  if self._last_light_move > 0.15 then
    self._last_light_move = 0
    if self.lights then

      self.fuel_gauge:set_properties({ glow = self._show_lights and 10 or 0 })
      self.lights:set_properties({ textures = { self._show_lights and "automobiles_front_lights.png" or "automobiles_white.png" }, glow = self._show_lights and 15 or 0 })

      if not is_braking and self.r_lights then
        local rear_tex = self._show_lights and "automobiles_rear_lights.png" or "automobiles_rear_lights_off.png"
        local rear_glow = self._show_lights and 10 or 0
        self.r_lights:set_properties({ textures = { rear_tex }, glow = rear_glow })
      end

      if self._show_lights then
        automobiles_lib.put_light(self)
      else
        automobiles_lib.remove_light(self)
      end
    end
  end

  -- Handle control and autodrive
  if is_attached then
    local impact = automobiles_lib.get_hipotenuse_value(velocity, self.lastvelocity)
    if impact > 1 and self._last_time_collision_snd > 0.3 then
      self._last_time_collision_snd = 0
      minetest.sound_play("collision", {
        to_player = self.owner,
        gain = 1.0,
        fade = 0.0,
        pitch = 1.0,
      })
    end

    -- Steering dynamics
    local steering_angle_max = 40
    local steering_speed = 40
    if math.abs(longit_speed) > 3 * self._vehicle_scale then
      local mid_speed = steering_speed / 2
      steering_speed = mid_speed + (mid_speed / math.abs(longit_speed * 0.25)) * self._vehicle_scale
    end

    -- Transmission emulation
    local acc_factor = self._max_acc_factor
    local transmission_state = automobiles_lib.get_transmission_state(self, longit_speed, self._max_speed)
    local target_acc_factor = acc_factor

    if self._have_transmission ~= false then
      if transmission_state == 1 then
        target_acc_factor = acc_factor / 3
      elseif transmission_state == 2 then
        target_acc_factor = acc_factor / 2
      end
      self._transmission_state = transmission_state
    end

    -- Autodrive or manual control
    if self._autodrive_active and autodrive then
      autodrive.update(self, dtime)
    else
      local control = self._control_function or automobiles_lib.control
      accel, stop = control(self, dtime, hull_direction, longit_speed, longit_speed_drag, later_drag, accel,
        target_acc_factor, self._max_speed, steering_angle_max, steering_speed)
    end
  else
    self._show_lights = false
    if self.sound_handle then
      minetest.sound_stop(self.sound_handle)
      self.sound_handle = nil
    end
  end

  local angle_factor = self._steering_angle / 10
  
  -- Helper: set wheel attachment
  local function attach_wheel(wheel, suspension, x_offset, rotation_y)
    if wheel and suspension then
      wheel:set_attach(suspension, '', { x = x_offset, y = 0, z = 0 }, { x = 0, y = rotation_y, z = 0 })
    end
  end

  -- Wheel turn (only when not flying)
  if self.lf_wheel and self.rf_wheel and self.lr_wheel and self.rr_wheel and self._is_flying ~= 1 then
    attach_wheel(self.lf_wheel, self.front_suspension, -self._front_wheel_xpos, -self._steering_angle - angle_factor)
    attach_wheel(self.rf_wheel, self.front_suspension,  self._front_wheel_xpos, (-self._steering_angle + angle_factor) + 180)
    attach_wheel(self.lr_wheel, self.rear_suspension,  -self._rear_wheel_xpos, 0)
    attach_wheel(self.rr_wheel, self.rear_suspension,   self._rear_wheel_xpos, 180)
  end

  -- Helper: set wheel animation speed
  local function set_wheel_speed(wheel, speed)
    if wheel then wheel:set_animation_frame_speed(speed) end
  end

  -- Check if tires are touching pavement
  local noded = automobiles_lib.nodeatpos(automobiles_lib.pos_shift(curr_pos,
    { y = self.initial_properties.collisionbox[2] - 0.5 }))

  if noded and noded.drawtype ~= 'airlike' and noded.drawtype ~= 'liquid' then
    local wheel_comp = longit_speed * (self._wheel_compensation or 1)
    set_wheel_speed(self.lf_wheel, wheel_comp * (12 - angle_factor))
    set_wheel_speed(self.rf_wheel, -wheel_comp * (12 + angle_factor))
    set_wheel_speed(self.lr_wheel, wheel_comp * (12 - angle_factor))
    set_wheel_speed(self.rr_wheel, -wheel_comp * (12 + angle_factor))
  else
    -- Flying animation
    set_wheel_speed(self.lf_wheel, 1)
    set_wheel_speed(self.rf_wheel, -1)
    set_wheel_speed(self.lr_wheel, 1)
    set_wheel_speed(self.rr_wheel, -1)
  end

  -- Drive wheel turn
  local drive_rotation = { x = 0, y = 0, z = self._steering_angle * 2 }
  if self._steering_ent then
    self.steering:set_attach(self.steering_axis, '', { x = 0, y = 0, z = 0 }, drive_rotation)
  else
    self.object:set_bone_position("drive_wheel", { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = -drive_rotation.z })
  end

  -- Adjust yaw based on steering
  if math.abs(self._steering_angle) > 5 then
    local turn_rate = math.rad(40)
    newyaw = yaw + dtime * (1 - 1 / (math.abs(longit_speed) + 1)) *
      self._steering_angle / 30 * turn_rate * automobiles_lib.sign(longit_speed)
  end

  -- Turn light logic
  if self.turn_l_light and self.turn_r_light then
    local function set_turn_light_properties(tex, glow)
      self.turn_l_light:set_properties({ textures = tex, glow = glow })
      self.turn_r_light:set_properties({ textures = tex, glow = glow })
    end

    local function get_light_texture_and_glow(state)
      local tex = state and (self._textures_turn_lights_on or { "automobiles_rear_lights_full.png" })
                or (self._textures_turn_lights_off or { "automobiles_rear_lights_off.png" })
      local glow = state and 20 or 0
      return tex, glow
    end

    -- Turn signal logic
    if not self._key_flash_active then
      self._turn_light_timer = self._turn_light_timer + dtime
      if self._turn_light_timer >= 0.5 then
        self._turn_light_timer = 0
        self._turn_light_on = not self._turn_light_on

        local tex, glow = get_light_texture_and_glow(self._turn_light_on)

        if math.abs(self._steering_angle) > 15 then
          if self._steering_angle < 0 then
            self.turn_r_light:set_properties({ textures = tex, glow = glow })
          elseif self._steering_angle > 0 then
            self.turn_l_light:set_properties({ textures = tex, glow = glow })
          end
        else
          local off_tex = self._textures_turn_lights_off or { "automobiles_rear_lights_off.png" }
          self.turn_l_light:set_properties({ textures = off_tex, glow = 0 })
          self.turn_r_light:set_properties({ textures = off_tex, glow = 0 })
          self._turn_light_on = false
        end
      end
    end

    -- Key flash logic
    if self._key_flash_active then
      self._key_flash_timer = self._key_flash_timer + dtime
      if self._key_flash_timer >= 0.5 then
        self._key_flash_timer = 0
        self._key_flash_on = not self._key_flash_on
        self._key_flash_count = self._key_flash_count - 1

        local tex, glow = get_light_texture_and_glow(self._key_flash_on)
        set_turn_light_properties(tex, glow)

        if self._key_flash_count <= 0 then
          self._key_flash_active = false
          self._key_flash_on = false
        end
      end
    end
  end

  -- Acceleration correction to prevent overflow crash
  local MAX_ACCEL = 25
  accel.x = math.max(-MAX_ACCEL, math.min(accel.x, MAX_ACCEL))
  accel.z = math.max(-MAX_ACCEL, math.min(accel.z, MAX_ACCEL))

  -- Energy consumption
  if self._energy > 0 then
    if not automobiles_lib.is_drift_game then
      self._energy = self._energy - (automobiles_lib.get_hipotenuse_value(accel, vector.new()) / (self._consumption_divisor or 80000))
    else
      self._energy = 5
    end
  end

  -- Handle fuel depletion
  if self._energy <= 0 then
    self._engine_running = false
    self._is_flying = 0
    if self.sound_handle then
      minetest.sound_stop(self.sound_handle)
      self.sound_handle = nil
      minetest.chat_send_player(self.owner, "Out of fuel")
    end
  else
    self._last_engine_sound_update = self._last_engine_sound_update + dtime
    if self._last_engine_sound_update > 0.3 then
      self._last_engine_sound_update = 0
      automobiles_lib.engine_set_sound_and_animation(self, longit_speed)
    end
  end

  -- Update fuel gauge
  if self.fuel_gauge then
    self.fuel_gauge:set_attach(self.object, '', self._fuel_gauge_pos, { x = 0, y = 0, z = automobiles_lib.get_gauge_angle(self._energy) })
  end

  -- Gravity application
  if not self._is_flying or self._is_flying == 0 then
    accel.y = -automobiles_lib.gravity
  else
    accel.y = self._car_gravity * (self.dtime / automobiles_lib.ideal_step)
  end

  -- Apply acceleration or stop
  if stop then
    self._last_accel = vector.new()
    self.object:set_acceleration({ x = 0, y = 0, z = 0 })
    self.object:set_velocity({ x = 0, y = 0, z = 0 })
  else
    self.object:move_to(curr_pos)
    local limit = self._max_speed / self.dtime
    if accel.y > limit then accel.y = limit end
    self._last_accel = accel
  end

  -- Ground check
  self._last_ground_check = self._last_ground_check + dtime
  if self._last_ground_check > 0.18 then
    self._last_ground_check = 0
    automobiles_lib.ground_get_distances(self, 0.372 * self._vehicle_scale,
      (self._front_suspension_pos.z * self._vehicle_scale) / 10)
  end

  -- Pitch and roll calculation
  local newpitch = self._pitch
  local newroll = self._roll or 0
  local turn_speed = math.min(longit_speed, self._is_motorcycle and 20 or 10)

  if self._is_flying == 1 then
    newpitch = 0
    newroll = math.abs(self._steering_angle) < 1 and 0 or (-self._steering_angle / 100) * (turn_speed / 10)

    local max_pitch = 6
    local h_vel_comp = math.min(max_pitch, math.max(0, (((longit_speed * 2) * 100) / max_pitch) / 100))
    newpitch = newpitch + (velocity.y * math.rad(max_pitch - h_vel_comp))
  else
    if self._is_motorcycle then
      newroll = (-self._steering_angle / 100) * (turn_speed / 10)
      if not is_attached and stop then
        newroll = self._stopped_roll
      end
    elseif math.abs(longit_speed) > 0 then
      local tilt = math.min(10, math.max(-10, (-later_speed / 12) * (turn_speed / 30)))
      newroll = -tilt + (self._roll or 0)
      self.front_suspension:set_rotation({ x = 0, y = 0, z = tilt })
      self.rear_suspension:set_rotation({ x = 0, y = 0, z = tilt })

      if noded and noded.drawtype ~= 'airlike' and noded.drawtype ~= 'liquid' then
        local min_later_speed = self._min_later_speed or 3
        local smoke_threshold = min_later_speed / 2
        if math.abs(later_speed) > smoke_threshold and not self._is_motorcycle then
          automobiles_lib.add_smoke(self, curr_pos, yaw, self._rear_wheel_xpos * self._vehicle_scale)

          if not automobiles_lib.extra_drift and self._last_time_drift_snd >= 2.0 and
             math.abs(later_speed) > min_later_speed then
            self._last_time_drift_snd = 0
            minetest.sound_play("automobiles_drifting", {
              pos = curr_pos,
              max_hear_distance = 20,
              gain = 3.0,
              fade = 0.0,
              pitch = 1.0,
              ephemeral = true,
            })
          end
        end
      end
    else
      self.front_suspension:set_rotation({ x = 0, y = 0, z = 0 })
      self.rear_suspension:set_rotation({ x = 0, y = 0, z = 0 })
    end
  end

  -- Apply final rotation
  self.object:set_rotation({ x = newpitch, y = newyaw, z = newroll })
  self._longit_speed = longit_speed

end

-- Key System Helpers
function automobiles_lib.has_authorized_key(player, car_owner)
  local inv = player:get_inventory()
  for _, listname in ipairs({"main", "craft"}) do
    local list = inv:get_list(listname)
    for i = 1, #list do
      local stack = list[i]
      if stack:get_name():match("automobiles_lib:%w+_key") then
        local meta = stack:get_meta()
        if meta:get("paired_owner") == car_owner then
          return true
        end
      end
    end
  end
  return false
end

-- New: Dedicated button functions (called from formspec fields handler)
function automobiles_lib.key_toggle_lock(ent, player_name)
  if not ent or not ent.object then
    smartlog(player_name, S("Invalid car reference."))
    return
  end
  local S = automobiles_lib.S
  ent._locked = not ent._locked
  local action = ent._locked and "lock" or "unlock"
  minetest.sound_play({name = "lock_unlock_sfx"}, {pos = ent.object:get_pos(), gain = 0.6, max_hear_distance = 32, loop = false})
  if automobiles_lib.flash_turn_signals then
    automobiles_lib.flash_turn_signals(ent, action)
  end
  minetest.chat_send_player(player_name, ent._locked and S("Car locked.") or S("Car unlocked."))
  minetest.log("action", player_name .. " toggled lock on car ID '" .. (ent.car_id or "unknown") .. "'")
end

function automobiles_lib.key_panic(ent)
  if not ent or not ent.object then return end
  local S = automobiles_lib.S
  -- Panic: Continuous horn (assumes flash_turn_signals handles sound for "panic")
  if automobiles_lib.flash_turn_signals then
    automobiles_lib.flash_turn_signals(ent, "panic")
  end
end

function automobiles_lib.key_locate(ent)
  if not ent or not ent.object then return end
  local S = automobiles_lib.S
  -- Locate: Flash + sound (assumes flash_turn_signals does visuals/sound for "locate")
  minetest.sound_play({name = ent._horn_sound or "automobiles_horn"}, {pos = pos, gain = 1.3, max_hear_distance = 100, loop = false})
  automobiles_lib.flash_turn_signals(ent, "locate")
end

function automobiles_lib.key_unpair(player)
  local name = player:get_player_name()
  local wield_index = player:get_wield_index()
  local inv = player:get_inventory()
  local wielded = player:get_wielded_item()
  local wname = wielded:get_name()

  -- Remove the held item completely
  inv:set_stack("main", wield_index, nil)

  -- Create a fresh unpaired key of the same type
  local key_type = wname:gsub("automobiles_lib:", "")
  local new_key_name = "automobiles_lib:" .. key_type
  local new_key = ItemStack(new_key_name)
  local new_meta = new_key:get_meta()

  -- Place the new key in the same slot
  inv:set_stack("main", wield_index, new_key)

  minetest.chat_send_player(name, S("Key has been unpaired."))
  minetest.log("action", "Player " .. name .. " unpaired and refreshed key")
end


-- Ensure flash_turn_signals is defined (from earlier; add if missing)
function automobiles_lib.flash_turn_signals(self, action)
  if not self then return end
  local sound = nil

  if action == "panic" then
    sound = minetest.sound_play({name = self._horn_sound or "automobiles_horn"}, {pos = self.object:get_pos(), gain = 1.3, max_hear_distance = 50, loop = true})
    minetest.after(30, function() minetest.sound_stop(sound) end)  -- Stop after 30s bc bruh
    return  -- Only sound for panic
  end
  -- elseif action == "locate" then
  --   sound = "default_place_node"  -- Or custom
  --   minetest.sound_play({name = sound}, {pos = self.object:get_pos(), gain = 1.0, max_hear_distance = 50})
  -- end

  self._key_flash_active = true
  self.key_flash=2
end