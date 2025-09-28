-- automobiles_NG
automobiles_lib = {
  storage = minetest.get_mod_storage()
}

automobiles_lib.S = nil

if (minetest.get_translator ~= nil) then
  automobiles_lib.S = minetest.get_translator(minetest.get_current_modname())
else
  automobiles_lib.S = function(s) return s end
end

local S = automobiles_lib.S
local storage = automobiles_lib.storage
local debug_enabled = {}

automobiles_lib.is_minetest = core.get_modpath("player_api")
automobiles_lib.is_mcl = core.get_modpath("mcl_player")
automobiles_lib.is_repixture = core.get_modpath("rp_player")

automobiles_lib.fuel = {
  ['biofuel:biofuel'] = 1,
  ['biofuel:bottle_fuel'] = 1,
  ['biofuel:phial_fuel'] = 0.25,
  ['biofuel:fuel_can'] = 10,
  ['airutils:biofuel'] = 1,
}

automobiles_lib.gravity = 9.8
automobiles_lib.ideal_step = 0.2
automobiles_lib.is_creative = minetest.settings:get_bool("creative_mode", false)
automobiles_lib.can_collect_car = minetest.settings:get_bool("collect_automobiles", true)

automobiles_lib.is_drift_game = false
automobiles_lib.extra_drift = false
if minetest.registered_nodes["dg_mapgen:stone"] then
  automobiles_lib.is_drift_game = true
  automobiles_lib.extra_drift = true
end

local load_noob_mode = minetest.settings:get_bool("noob_mode", false) -- or storage:get_int("noob_mode")
automobiles_lib.noob_mode = false
automobiles_lib.extra_stepheight = 0
-- 1 == true ---- 2 == false
if load_noob_mode == true then
  automobiles_lib.load_noob_mode = true
  automobiles_lib.extra_stepheight = 1
end

local motorcycle_anim_mode = minetest.settings:get_bool("motorcycle_anim_mode", true)
automobiles_lib.mot_anim_mode = true
if motorcycle_anim_mode == false or automobiles_lib.is_mcl then --disable for mcl too -- TODO
  automobiles_lib.mot_anim_mode = false
end


--cars colors
automobiles_lib.colors = {
  black = '#2b2b2b',
  blue = '#0063b0',
  brown = '#8c5922',
  cyan = '#07B6BC',
  dark_green = '#567a42',
  dark_grey = '#6d6d6d',
  green = '#4ee34c',
  grey = '#9f9f9f',
  magenta = '#ff0098',
  orange = '#ff8b0e',
  pink = '#ff62c6',
  red = '#dc1818',
  violet = '#a437ff',
  white = '#FFFFFF',
  yellow = '#ffe400',
}

local eye_height_plus_value = 6.5
local base_eie_height = -4
if automobiles_lib.is_mcl then
  base_eie_height = -5.5
end

--
-- helpers and co.
--
function smartlog(player_name, message)
    if debug_enabled[player_name] then
        minetest.chat_send_player(player_name, message)
    end
end
minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    debug_enabled[name] = nil
end)


-- NEW: Generate unique ID for car (hash owner + timestamp)
function generate_car_id(owner_name)
  local timestamp = os.time()
  local seed = "car:" .. owner_name .. ":" .. timestamp
  return minetest.sha1(seed):sub(1, 8) -- Short, unique hash (first 8 chars for simplicity)
end

function automobiles_lib.get_hipotenuse_value(point1, point2)
  return math.sqrt((point1.x - point2.x) ^ 2 + (point1.y - point2.y) ^ 2 + (point1.z - point2.z) ^ 2)
end

function automobiles_lib.dot(v1, v2)
  return (v1.x * v2.x) + (v1.y * v2.y) + (v1.z * v2.z)
end

function automobiles_lib.sign(n)
  return n >= 0 and 1 or -1
end

function automobiles_lib.minmax(v, m)
  return math.min(math.abs(v), m) * minekart.sign(v)
end

function automobiles_lib.properties_copy(origin_table)
  local tablecopy = {}
  for k, v in pairs(origin_table) do
    tablecopy[k] = v
  end
  return tablecopy
end

local function smoke_particle(self, pos)
  minetest.add_particle({
    pos = pos,
    velocity = { x = 0, y = 0, z = 0 },
    acceleration = { x = 0, y = 0, z = 0 },
    expirationtime = 0.25,
    size = 2.8 * (self._vehicle_scale or 1),
    collisiondetection = false,
    collision_removal = false,
    vertical = false,
    texture = "automobiles_smoke.png",
  })
end

function automobiles_lib.add_smoke(self, pos, yaw, rear_wheel_xpos)
  local direction = yaw

  --right
  local move = rear_wheel_xpos / 10
  local smk_pos = vector.new(pos)
  smk_pos.x = smk_pos.x + move * math.cos(direction)
  smk_pos.z = smk_pos.z + move * math.sin(direction)

  smoke_particle(self, smk_pos)

  --left
  direction = direction - math.rad(180)
  smk_pos = vector.new(pos)
  smk_pos.x = smk_pos.x + move * math.cos(direction)
  smk_pos.z = smk_pos.z + move * math.sin(direction)

  smoke_particle(self, smk_pos)
end

--returns 0 for old, 1 for new
function automobiles_lib.detect_player_api(player)
  local player_proterties = player:get_properties()
  --local mesh = "character.b3d"
  --if player_proterties.mesh == mesh then
  if core.get_modpath("player_api") then
    local models = player_api.registered_models
    local character = models[player_proterties.mesh]
    --core.chat_send_all(dump(character));
    if character then
      if character.animations.sit.eye_height then
        --core.chat_send_all(dump(character.animations.sit.eye_height));
        if character.animations.sit.eye_height == 0.8 then
          --core.chat_send_all("new model");
          return 1
        else
          --core.chat_send_all("new height");
          return 2 --strange bug with armor ands skins returning 1.47
        end
      else
        --core.chat_send_all("old model");
        return 0
      end
    end
  end

  return 0
end

function automobiles_lib.seats_create(self)
  if self.object then
    local pos = self.object:get_pos()
    self._passengers_base = {}
    self._passengers = {}
    if self._seat_pos then
      local max_seats = table.getn(self._seat_pos)
      for i = 1, max_seats do
        self._passengers_base[i] = minetest.add_entity(pos, 'automobiles_lib:pivot_mesh')
        if not self._seats_rot then
          self._passengers_base[i]:set_attach(self.object, '', self._seat_pos[i], { x = 0, y = 0, z = 0 })
        else
          self._passengers_base[i]:set_attach(self.object, '', self._seat_pos[i],
            { x = 0, y = self._seats_rot[i], z = 0 })
        end
      end

      self.driver_seat = self._passengers_base[1]    --sets pilot seat reference
      self.passenger_seat = self._passengers_base[2] --sets copilot seat reference
    end
  end
end

function automobiles_lib.sit(player)
  --set_animation(frame_range, frame_speed, frame_blend, frame_loop)
  player:set_animation({ x = 81, y = 160 }, 30, 0, true)
  if core.get_modpath("emote") then emote.start(player:get_player_name(), "sit") end
end

-- attach player
function automobiles_lib.attach_driver(self, player)
  minetest.sound_play({ name = (self._door_sound or "automobiles_door") },{
        object = self.object,
        gain = 4,
        pitch = snd_pitch,
        max_hear_distance = 10,
        loop = false,
      })
  local name = player:get_player_name()
  self.driver_name = name
  -- attach the driver
  player:set_attach(self.driver_seat, "", { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
  local eye_y = base_eie_height
  if automobiles_lib.detect_player_api(player) == 1 then
    eye_y = eye_y + eye_height_plus_value
  end
  eye_y = eye_y * self._vehicle_scale

  player:set_eye_offset({ x = 0, y = eye_y, z = 0 }, { x = 0, y = eye_y, z = -30 })

  if automobiles_lib.is_minetest then
    player_api.player_attached[name] = true
    player_api.set_animation(player, "sit")
  elseif airutils.is_mcl then
    mcl_player.player_attached[name] = true
    mcl_player.player_set_animation(player, "sit", 30)
    automobiles_lib.sit(player)
  end

  -- make the driver sit
  minetest.after(1, function()
    if player then
      --minetest.chat_send_all("okay")
      automobiles_lib.sit(player)
      --apply_physics_override(player, {speed=0,gravity=0,jump=0})
    end
  end)
end

function automobiles_lib.dettach_driver(self, player)
  local name = self.driver_name
  minetest.sound_play({ name = (self._door_sound or "automobiles_door") },{
        object = self.object,
        gain = 4,
        pitch = snd_pitch,
        max_hear_distance = 10,
        loop = false,
      })
  --self._engine_running = false

  -- driver clicked the object => driver gets off the vehicle
  self.driver_name = nil

  if self._engine_running then
    self._engine_running = false
  end
  -- sound and animation
  if self.sound_handle then
    minetest.sound_stop(self.sound_handle)
    self.sound_handle = nil
  end
  pcall(automobiles_lib.radio_stop, self)

  -- detach the player
  if player.set_detach then
    --automobiles_lib.remove_hud(player)

    --player:set_properties({physical=true})
    player:set_detach()
    player:set_eye_offset({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    if automobiles_lib.is_minetest then
      if player_api.player_attached[name] then
        player_api.player_attached[name] = nil
      end
      player_api.set_animation(player, "stand")
    elseif automobiles_lib.is_mcl then
      if mcl_player.player_attached[name] then
        mcl_player.player_attached[name] = nil
      end
      mcl_player.player_set_animation(player, "stand")
    end
  end
  self.driver = nil
end

-- attach passenger
function automobiles_lib.attach_pax(self, player, onside)
  onside = onside or false
  local name = player:get_player_name()

  local eye_y = base_eie_height
  if automobiles_lib.detect_player_api(player) == 1 then
    eye_y = eye_y + eye_height_plus_value
  end
  eye_y = eye_y * self._vehicle_scale

  if self._passenger == nil then
    self._passenger = name
    self._passengers[2] = name  -- ADD THIS LINE: Unify with multi-passenger tracking

    -- attach the pax
    player:set_attach(self.passenger_seat, "", { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    player:set_eye_offset({ x = 0, y = eye_y, z = 0 }, { x = 0, y = eye_y, z = -30 })
    if automobiles_lib.is_minetest then
      player_api.player_attached[name] = true
      player_api.set_animation(player, "sit")
    elseif airutils.is_mcl then
      mcl_player.player_attached[name] = true
      mcl_player.player_set_animation(player, "sit", 30)
      automobiles_lib.sit(player)
    end

    -- make the pax sit
    minetest.after(0.2, function()
      if player then
        --minetest.chat_send_all("okay")
        automobiles_lib.sit(player)
        --apply_physics_override(player, {speed=0,gravity=0,jump=0})
      end
    end)
  else
    --randomize the seat
    local max_seats = table.getn(self._seat_pos) --driver and front passenger

    t = {}                                       -- new array
    for i = 1, max_seats do                      --(the first are for the driver
      t[i] = i
    end

    for i = 1, #t * 2 do
      local a = math.random(#t)
      local b = math.random(#t)
      t[a], t[b] = t[b], t[a]
    end

    for k, v in ipairs(t) do
      i = t[k]
      if self._passengers[i] == nil and i > 2 then
        --core.chat_send_all(self.driver_name)
        self._passengers[i] = name
        player:set_attach(self._passengers_base[i], "", { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
        player:set_eye_offset({ x = 0, y = eye_y, z = 0 }, { x = 0, y = 3, z = -30 })
        if automobiles_lib.is_minetest then
          player_api.player_attached[name] = true
          player_api.set_animation(player, "sit")
        elseif airutils.is_mcl then
          mcl_player.player_attached[name] = true
          mcl_player.player_set_animation(player, "sit", 30)
          automobiles_lib.sit(player)
        end

        -- make the pax sit
        minetest.after(0.2, function()
          if player then
            --minetest.chat_send_all("okay")
            automobiles_lib.sit(player)
            --apply_physics_override(player, {speed=0,gravity=0,jump=0})
          end
        end)
        break
      end
    end
  end
  minetest.chat_send_all(dump(self._passengers))  -- Now this won't be empty for front passenger
end

function automobiles_lib.dettach_pax(self, player)
  if not player then return end
  local name = player:get_player_name() --self._passenger

  -- Clear passenger tracking (your existing logic)
  -- passenger clicked the object => driver gets off the vehicle
  local is_driver_exiting = false
  if self.driver_name == name then
    is_driver_exiting = true
    -- Assuming driver exit clears _passenger[1] or similar; adjust if needed
    self._passenger = nil
    self._passengers[1] = nil  -- If driver uses index 1
  elseif self._passenger == name then
    self._passenger = nil
    self._passengers[2] = nil
  else
    local max_seats = table.getn(self._seat_pos)
    for i = max_seats, 1, -1 do
      if self._passengers[i] == name then
        self._passengers[i] = nil
        break
      end
    end
  end

  -- Detach the player (your existing logic)
  if player then
    local pos = player:get_pos()
    player:set_detach()

    if automobiles_lib.is_minetest then
      if player_api.player_attached[name] then
        player_api.player_attached[name] = nil
      end
      player_api.set_animation(player, "stand")
    elseif automobiles_lib.is_mcl then
      if mcl_player.player_attached[name] then
        mcl_player.player_attached[name] = nil
      end
      mcl_player.player_set_animation(player, "stand")
    end

    player:set_eye_offset({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })
    --remove_physics_override(player, {speed=1,gravity=1,jump=1})

    -- NEW/ENHANCED: Stop radio sounds on detach
    minetest.log("action", "DEBUG: dettach_pax called for '" .. name .. "' (is driver? " .. tostring(is_driver_exiting) .. ")")

    -- Stop the exiting player's sound specifically
    if self.radio_handles and self.radio_handles[name] then
      local handle = self.radio_handles[name]
      if handle and type(handle) == "number" then
        minetest.sound_stop(handle)
        minetest.log("action", "DEBUG: Stopped exiting player '" .. name .. "' sound (handle: " .. tostring(handle) .. ")")
      else
        minetest.log("action", "DEBUG: No valid handle for exiting '" .. name .. "' (got: " .. tostring(handle) .. ")")
      end
      self.radio_handles[name] = nil
    elseif self.radio_handles then
      minetest.log("action", "DEBUG: No handle entry for '" .. name .. "' in radio_handles")
    else
      minetest.log("action", "DEBUG: No radio_handles table on detach for '" .. name .. "'")
    end

    -- If driver is exiting, stop ALL sounds (shutdown radio for vehicle)
    if is_driver_exiting then
      minetest.log("action", "DEBUG: Driver exiting - stopping all radio sounds")
      automobiles_lib.radio_stop(self)
      -- Optional: Eject all passengers too? If yes, add loop over _passengers and call dettach_pax for each.
    end
  end
end

function automobiles_lib.get_gauge_angle(value, initial_angle)
  initial_angle = initial_angle or 90
  local angle = value * 18
  angle = angle - initial_angle
  angle = angle * -1
  return angle
end

function automobiles_lib.setText(self, vehicle_name)
  local properties = self.object:get_properties()
  local formatted = ""
  if self.hp_max then
    formatted = S(" Current hp: ") .. string.format(
      "%.2f", self.hp_max
    )
  end
  if properties then
    properties.infotext = S("Nice @1 of @2.@3", vehicle_name, self.owner, formatted)
    self.object:set_properties(properties)
  end
end

function automobiles_lib.get_xz_from_hipotenuse(orig_x, orig_z, yaw, distance)
  --cara, o minetest é bizarro, ele considera o eixo no sentido ANTI-HORÁRIO... Então pra equação funcionar, subtrair o angulo de 360 antes
  yaw = math.rad(360) - yaw
  local z = (math.cos(yaw) * distance) + orig_z
  local x = (math.sin(yaw) * distance) + orig_x
  return x, z
end

function automobiles_lib.remove_light(self)
  if self._light_old_pos then
    --force the remotion of the last light
    minetest.add_node(self._light_old_pos, { name = "air" })
    self._light_old_pos = nil
  end
end

function automobiles_lib.swap_node(self, pos)
  local target_pos = pos
  local have_air = false
  local node = nil
  local count = 0
  while have_air == false and count <= 3 do
    node = minetest.get_node(target_pos)
    if node.name == "air" then
      have_air = true
      break
    end
    count = count + 1
    target_pos.y = target_pos.y + 1
  end

  if have_air then
    minetest.set_node(target_pos, { name = 'automobiles_lib:light' })
    automobiles_lib.remove_light(self)
    self._light_old_pos = target_pos
    --remove after one second
    --[[minetest.after(1,function(target_pos)
            local node = minetest.get_node_or_nil(target_pos)
            if node and node.name == "automobiles_lib:light" then
                minetest.swap_node(target_pos, {name="air"})
            end
        end, target_pos)]] --

    return true
  end
  return false
end

function automobiles_lib.put_light(self)
  local pos = self.object:get_pos()
  pos.y = pos.y + 1
  local yaw = self.object:get_yaw()
  local lx, lz = automobiles_lib.get_xz_from_hipotenuse(pos.x, pos.z, yaw, 10)
  local light_pos = { x = lx, y = pos.y, z = lz }

  local cast = minetest.raycast(pos, light_pos, false, false)
  local thing = cast:next()
  local was_set = false
  while thing do
    if thing.type == "node" then
      local ipos = thing.intersection_point
      if ipos then
        was_set = automobiles_lib.swap_node(self, ipos)
      end
    end
    thing = cast:next()
  end
  if was_set == false then
    local n = minetest.get_node_or_nil(light_pos)
    if n and n.name == 'air' then
      automobiles_lib.swap_node(self, light_pos)
    end
  end


  --[[local n = minetest.get_node_or_nil(light_pos)
    --minetest.chat_send_player(name, n.name)
    if n and n.name == 'air' then
        minetest.set_node(pos, {name='automobiles_lib:light'})
        --local timer = minetest.get_node_timer(pos)
        --timer:set(10, 0)
        minetest.after(0.3,function(pos)
            local node = minetest.get_node_or_nil(pos)
            if node and node.name == "automobiles_lib:light" then
                minetest.swap_node(pos, {name="air"})
            end
        end, pos)
    end]] --
end

function automobiles_lib.seats_destroy(self)
  local max_seats = table.getn(self._passengers_base)
  for i = 1, max_seats do
    if self._passengers_base[i] then self._passengers_base[i]:remove() end
  end
end

function automobiles_lib.destroy(self, puncher)
  if self.driver_name then
    -- detach the driver first (puncher must be driver)
    if puncher then
      puncher:set_detach()
      puncher:set_eye_offset({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })

      if automobiles_lib.is_minetest then
        if player_api.player_attached[self.driver_name] then
          player_api.player_attached[self.driver_name] = nil
        end
        player_api.set_animation(player, "stand")
      elseif automobiles_lib.is_mcl then
        if mcl_player.player_attached[self.driver_name] then
          mcl_player.player_attached[self.driver_name] = nil
        end
        mcl_player.player_set_animation(player, "stand")
      end
    end
    self.driver_name = nil
  end
  -- Stop any engine sound if playing
  if self.sound_handle then
    minetest.sound_stop(self.sound_handle)
    minetest.sound_stop(self.sound_handle)
    minetest.sound_stop(self.sound_handle)
    minetest.sound_stop(self.sound_handle)
    minetest.sound_stop(self.sound_handle)
    minetest.sound_stop(self.sound_handle)
    minetest.sound_stop(self.sound_handle)
    minetest.sound_stop(self.sound_handle)
    minetest.sound_stop(self.sound_handle)
    minetest.sound_stop(self.sound_handle)
    self.sound_handle = nil
  end
  --H*LY SH*T WHY DOES IT WORK. THATS SO STUPID
  --minetest.chat_send_player(puncher:get_player_name(), "Destroying in " .. (self._engine_delay or 0.6) + 0.2)
  minetest.after((self._engine_delay or 0.6) + 0.2, function()
    local pos = self.object:get_pos()

    if self.front_suspension then self.front_suspension:remove() end
    if self.lf_wheel then self.lf_wheel:remove() end
    if self.rf_wheel then self.rf_wheel:remove() end
    if self.rear_suspension then self.rear_suspension:remove() end
    if self.lr_wheel then self.lr_wheel:remove() end
    if self.rr_wheel then self.rr_wheel:remove() end
    if self.steering then self.steering:remove() end
    if self.steering_axis then self.steering_axis:remove() end
    if self.driver_seat then self.driver_seat:remove() end
    if self.passenger_seat then self.passenger_seat:remove() end
    if self.fuel_gauge then self.fuel_gauge:remove() end
    if self.lights then self.lights:remove() end
    if self.r_lights then self.r_lights:remove() end
    if self.reverse_lights then self.reverse_lights:remove() end
    if self.turn_l_light then self.turn_l_light:remove() end
    if self.turn_r_light then self.turn_r_light:remove() end
    if self.license_plate then 
      self.license_plate:remove()
      self.license_plate = nil
    end
    if self.rag then self.rag:remove() end                 --for buggy
    if self.back_seat then self.back_seat:remove() end     --for catrelle
    if self.instruments then self.instruments:remove() end --for delorean
    if self.normal_kit then self.normal_kit:remove() end
    if self.rag_rect then self.rag_rect:remove() end       --for roadster


    automobiles_lib.seats_destroy(self)
    automobiles_lib.destroy_inventory(self)
    automobiles_lib.remove_light(self);
    if self.sound_handle then
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      self.sound_handle = nil
    end

    if pos then
      pos.y = pos.y + 2


      if automobiles_lib.can_collect_car == false then
        minetest.add_item({ x = pos.x + math.random() - 0.5, y = pos.y, z = pos.z + math.random() - 0.5 },
          'automobiles_lib:engine')
        minetest.add_item({ x = pos.x + math.random() - 0.5, y = pos.y, z = pos.z + math.random() - 0.5 },
          'automobiles_lib:wheel')
        minetest.add_item({ x = pos.x + math.random() - 0.5, y = pos.y, z = pos.z + math.random() - 0.5 },
          'automobiles_lib:wheel')
        minetest.add_item({ x = pos.x + math.random() - 0.5, y = pos.y, z = pos.z + math.random() - 0.5 },
          'automobiles_lib:wheel')
        minetest.add_item({ x = pos.x + math.random() - 0.5, y = pos.y, z = pos.z + math.random() - 0.5 },
          'automobiles_lib:wheel')
      else
        local lua_ent = self.object:get_luaentity()
        local staticdata = lua_ent:get_staticdata(self)
        local obj_name = lua_ent.name

        local stack = ItemStack(obj_name)
        local stack_meta = stack:get_meta()
        stack_meta:set_string("staticdata", staticdata)

        if puncher then
          local inv = puncher:get_inventory()
          if inv then
            if inv:room_for_item("main", stack) then
              inv:add_item("main", stack)
            else
              minetest.add_item({ x = pos.x + math.random() - 0.5, y = pos.y, z = pos.z + math.random() - 0.5 }, stack)
            end
          end
        else
          minetest.add_item({ x = pos.x + math.random() - 0.5, y = pos.y, z = pos.z + math.random() - 0.5 }, stack)
        end
      end
    end
    if self.sound_handle then
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      minetest.sound_stop(self.sound_handle)
      self.sound_handle = nil
    end
    self.object:remove()
  end)
end

function automobiles_lib.engine_set_sound_and_animation(self, _longit_speed)
  local abs_curr_long_speed = math.abs(self._longit_speed)
  local abs_long_speed = math.abs(_longit_speed)
  local scale = self._vehicle_power_scale
  local range_spacing = 0.01
  if self.sound_handle then
    if (abs_curr_long_speed * scale > (abs_long_speed + range_spacing) * scale)
        or ((abs_curr_long_speed + range_spacing) * scale < abs_long_speed * scale) then
      --minetest.chat_send_all('test2')
      automobiles_lib.engineSoundPlay(self)
    end
  end
end

function automobiles_lib.engineSoundPlay(self)
  if self.sound_handle then minetest.sound_stop(self.sound_handle) end
  if self.object then
    local base_pitch = 1
    if self._base_pitch then base_pitch = self._base_pitch end

    local divisor = 100
    local multiplier = self._transmission_state or 1
    local engine_pitch_factor = self._engine_pitch_factor or 1
    local snd_pitch = base_pitch + ((((base_pitch / divisor) * multiplier) + ((self._longit_speed / 10) / 2)) * engine_pitch_factor)
    -- if self._transmission_state == 1 then
      -- snd_pitch = base_pitch + (self._longit_speed / 10)
    -- end

    self.sound_handle = minetest.sound_play({ name = self._engine_sound },
      {
        object = self.object,
        gain = 4,
        pitch = snd_pitch,
        max_hear_distance = 15,
        loop = true,
      })
  end
end

minetest.register_node("automobiles_lib:light", {
  drawtype = "airlike",
  --tile_images = {"automobiles_light.png"},
  inventory_image = minetest.inventorycube("automobiles_light.png"),
  paramtype = "light",
  walkable = false,
  is_ground_content = true,
  light_propagates = true,
  sunlight_propagates = true,
  light_source = 14,
  selection_box = {
    type = "fixed",
    fixed = { 0, 0, 0, 0, 0, 0 },
  },
})

function automobiles_lib.set_paint(self, puncher, itmstck)
  local is_admin = false
  is_admin = minetest.check_player_privs(puncher, { server = true })
  if not (self.owner == puncher:get_player_name() or is_admin == true) then
    return
  end

  local item_name = ""
  if itmstck then item_name = itmstck:get_name() end

  if item_name == "bike:painter" then
    --painting with bike painter
    local meta = itmstck:get_meta()
    local colstr = meta:get_string("paint_color")
    automobiles_lib.paint(self, colstr)
    return true
  else
    --painting with dyes
    local split = string.split(item_name, ":")
    local color, indx, _
    if split[1] then _, indx = split[1]:find('dye') end
    if indx then
      --[[for clr,_ in pairs(automobiles_lib.colors) do
                local _,x = split[2]:find(clr)
                if x then color = clr end
            end]] --
      --lets paint!!!!
      local color = (item_name:sub(indx + 1)):gsub(":", "")
      local colstr = automobiles_lib.colors[color]
      --minetest.chat_send_all(color ..' '.. dump(colstr))
      if colstr then
        automobiles_lib.paint(self, colstr)
        itmstck:set_count(itmstck:get_count() - 1)
        puncher:set_wielded_item(itmstck)
        return true
      end
      -- end painting
    end
  end
  return false
end

--painting
function automobiles_lib.paint(self, colstr, target_texture, second_painting_texture)
  target_texture = target_texture or "automobiles_painting.png"
  second_painting_texture = second_painting_texture or "automobiles_painting2.png"
  if colstr then
    self._color = colstr
    local l_textures = self.initial_properties.textures
    for _, texture in ipairs(l_textures) do
      local indx = texture:find(target_texture)
      if indx then
        l_textures[_] = target_texture .. "^[multiply:" .. colstr
      end
      indx = texture:find(second_painting_texture)
      if indx then
        l_textures[_] = second_painting_texture .. "^[multiply:" .. colstr
      end
    end
    self.object:set_properties({ textures = l_textures })
  end
end

function automobiles_lib.paint_with_mask(self, colstr, mask_colstr, target_texture, mask_texture)
  --"("..steampunk_blimp.canvas_texture.."^[mask:steampunk_blimp_rotor_mask2.png)^(default_wood.png^[mask:steampunk_blimp_rotor_mask.png)"

  target_texture = target_texture or "automobiles_painting.png"
  if colstr then
    self._color = colstr
    self._det_color = mask_colstr
    local l_textures = self.initial_properties.textures
    for _, texture in ipairs(l_textures) do
      local indx = texture:find(target_texture)
      if indx then
        --"("..target_texture.."^[mask:"..mask_texture..")"
        l_textures[_] = "(" ..
            target_texture ..
            "^[multiply:" .. colstr .. ")^(" .. target_texture .. "^[multiply:" .. mask_colstr ..
            "^[mask:" .. mask_texture .. ")"
      end
    end
    self.object:set_properties({ textures = l_textures })
  end
end

-- very basic transmission emulation for the car
function automobiles_lib.get_transmission_state(self, curr_speed, max_speed)
  local retVal = 1
  max_speed = max_speed or 100
  max_speed = max_speed * self._vehicle_scale
  curr_speed = curr_speed * self._vehicle_scale
  if curr_speed >= (max_speed / 4) then retVal = 2 end
  if curr_speed >= (max_speed / 2) then retVal = 3 end
  return retVal
end

dofile(minetest.get_modpath("automobiles_lib") .. DIR_DELIM .. "physics_lib.lua")
dofile(minetest.get_modpath("automobiles_lib") .. DIR_DELIM .. "custom_physics.lua")
dofile(minetest.get_modpath("automobiles_lib") .. DIR_DELIM .. "control.lua")
dofile(minetest.get_modpath("automobiles_lib") .. DIR_DELIM .. "fuel_management.lua")
dofile(minetest.get_modpath("automobiles_lib") .. DIR_DELIM .. "ground_detection.lua")
dofile(minetest.get_modpath("automobiles_lib") .. DIR_DELIM .. "painter.lua")
dofile(minetest.get_modpath("automobiles_lib") .. DIR_DELIM .. "inventory_management.lua")
dofile(minetest.get_modpath("automobiles_lib") .. DIR_DELIM .. "formspecs.lua")
dofile(minetest.get_modpath("automobiles_lib") .. DIR_DELIM .. "entities.lua")
dofile(minetest.get_modpath("automobiles_lib") .. DIR_DELIM .. "license_plate.lua")
-- yes, i definitely wanted you to drive off a fkin cliff
autodrive = dofile(minetest.get_modpath("automobiles_lib") .. DIR_DELIM .. "autodrive.lua")

-- engine
minetest.register_craftitem("automobiles_lib:engine", {
  description = S("Car Engine"),
  inventory_image = "automobiles_engine.png",
})

-- engine
minetest.register_craftitem("automobiles_lib:wheel", {
  description = S("Car Wheel"),
  inventory_image = "automobiles_wheel_icon.png",
})

if minetest.get_modpath("default") then
  minetest.register_craft({
    output = "automobiles_lib:engine",
    recipe = {
      { "default:steel_ingot", "default:steel_ingot", "default:steel_ingot" },
      { "default:steelblock",  "default:mese_block",  "default:steelblock" },
    }
  })
  minetest.register_craft({
    output = "automobiles_lib:wheel",
    recipe = {
      { "default:tin_ingot",   "default:steel_ingot", "default:tin_ingot" },
      { "default:steel_ingot", "default:steelblock",  "default:steel_ingot" },
      { "default:tin_ingot",   "default:steel_ingot", "default:tin_ingot" },
    }
  })
end

minetest.register_entity('automobiles_lib:wheel', {
  initial_properties = {
    physical = false,
    collide_with_objects = false,
    pointable = false,
    visual = "mesh",
    mesh = "automobiles_wheel.b3d",
    backface_culling = false,
    textures = { "automobiles_black.png", "automobiles_metal.png" },
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

minetest.register_privilege("valet_parking", {
  description = S("Gives a valet parking priv for a player"),
  give_to_singleplayer = true
})

minetest.register_chatcommand("transfer_vehicle", {
  params = "<new_owner>",
  description = S("Transfer the property of a vehicle to another player"),
  privs = { interact = true },
  func = function(name, param)
    local player = minetest.get_player_by_name(name)
    local target_player = minetest.get_player_by_name(param)
    local attached_to = player:get_attach()

    if attached_to ~= nil then
      if target_player ~= nil then
        local seat = attached_to:get_attach()
        if seat ~= nil then
          local entity = seat:get_luaentity()
          if entity then
            if entity.owner == name or minetest.check_player_privs(name, { protection_bypass = true }) then
              entity.owner = param
              minetest.chat_send_player(name,
                core.colorize('#00ff00', S(" >>> This vehicle now is property of: ") .. param))
              automobiles_lib.setText(entity, "vehicle")
            else
              minetest.chat_send_player(name,
                core.colorize('#ff0000', S(" >>> only the owner or moderators can transfer this vehicle")))
            end
          end
        end
      else
        minetest.chat_send_player(name, core.colorize('#ff0000', S(" >>> the target player must be logged in")))
      end
    else
      minetest.chat_send_player(name,
        core.colorize('#ff0000', S(" >>> you are not inside a vehicle to perform the command")))
    end
  end
})

minetest.register_chatcommand("lsaudio", {
    privs = {server = true},
    description = "Displays audio tracks.",
    func = function(name)
      for _, track in ipairs(automobiles_lib.scan_radio_tracks("automobiles_radio", "sounds")) do
          minetest.chat_send_player(name, "[Radio] " .. track.genre .. " - " .. track.name .. " by " .. track.artist)
      end
      return true
    end,
})
minetest.register_chatcommand("autodebug", {
    privs = {'autodebug'},
    description = "Toggles debug messages from the automobiles mod.",
    func = function(name)
        if debug_enabled[name] then
            debug_enabled[name] = nil
            return true, "Automobiles debug logging disabled."
        else
            debug_enabled[name] = true
            return true, "Automobiles debug logging enabled."
        end
    end,
})

--[[minetest.register_chatcommand("noobfy_the_vehicles", {
    params = "<true/false>",
    description = S("Enable/disable the NOOB mode for the vehicles"),
    privs = {server=true},
    func = function(name, param)
        local command = param

        if command == "false" then
            automobiles_lib.noob_mode = false
            automobiles_lib.extra_stepheight = 0
            minetest.chat_send_player(name, S(">>> Noob mode is disabled - A restart is required to changes take full effect"))
        else
            automobiles_lib.noob_mode = true
            automobiles_lib.extra_stepheight = 1
            minetest.chat_send_player(name, S(">>> Noob mode is enabled - A restart is required to changes take full effect"))
        end
        local save = 2
        if automobiles_lib.noob_mode == true then save = 1 end
        storage:set_int("noob_mode", save)
    end,
})]] --

-- Give to new player
if automobiles_lib.is_drift_game == true then
  minetest.register_on_joinplayer(function(player)
    local inv = player:get_inventory()
    local car = "automobiles_beetle:beetle"
    if not inv:contains_item("main", car) then inv:add_item("main", car) end
    car = "automobiles_buggy:buggy"
    if not inv:contains_item("main", car) then inv:add_item("main", car) end
    car = "automobiles_catrelle:catrelle_4f"
    if not inv:contains_item("main", car) then inv:add_item("main", car) end
    car = "automobiles_coupe:coupe"
    if not inv:contains_item("main", car) then inv:add_item("main", car) end
    car = "automobiles_delorean:delorean"
    if not inv:contains_item("main", car) then inv:add_item("main", car) end
    car = "automobiles_delorean:time_machine"
    if not inv:contains_item("main", car) then inv:add_item("main", car) end
    car = "automobiles_trans_am:trans_am"
    if not inv:contains_item("main", car) then inv:add_item("main", car) end
  end)
end

local old_entities = {
  "automobiles_buggy:pivot_mesh",
  "automobiles_buggy:pointer",
  "automobiles_catrelle:pivot_mesh",
  "automobiles_catrelle:pointer",
  "automobiles_catrelle:catrelle_tl",
  "automobiles_coupe:pivot_mesh",
  "automobiles_coupe:pointer",
  "automobiles_delorean:pivot_mesh",
  "automobiles_delorean:pointer",
  "automobiles_roadster:pivot_mesh",
  "automobiles_trans_am:pivot_mesh",
  "automobiles_trans_am:pointer",
  "automobiles_buggy:steering",
  "automobiles_vespa:pivot_mesh",
  "automobiles_motorcycle:pivot_mesh",
}


for _, entity_name in ipairs(old_entities) do
  minetest.register_entity(":" .. entity_name, {
    on_activate = function(self, staticdata)
      self.object:remove()
    end,
  })
end


-- Key System Items
local key_types = {
  { name = "basic_key",    image = "basic_key1.png",   desc = "Basic Car Key (Lock/Unlock)",                 recipe = { "mesecons_wireless:transmitter_off", "mesecons_fpga:fpga0000" } },
  { name = "fancy_key",    image = "fancy_key.png",    desc = "Fancy Car Key (Lock/Unlock/Panic)",           recipe = { "mesecons_wireless:transmitter_off", "mesecons_microcontroller:microcontroller0000" } },
  { name = "advanced_key", image = "advanced_key.png", desc = "Advanced Car Key (Lock/Unlock/Panic/Locate)", recipe = { "mesecons_wireless:transmitter_off", "mesecons_luacontroller:luacontroller0000" } },
}

for _, key in ipairs(key_types) do
  minetest.register_craftitem("automobiles_lib:" .. key.name, {
    description = key.desc,
    inventory_image = key.image, -- Grayscale base; tint via metadata (see pairing)
    stack_max = 1,               -- Keys are unique; no stacking abuse
    on_place = function(itemstack, placer, pointed_thing)
      return itemstack           -- Explicit no-op return to avoid interference
    end,
    -- UPDATED: on_use with pairing via car_id on right-click car (pointed_thing.ref → luaentity.car_id)
    -- If unpaired + pointed at car: Pair (set meta with car_id, color, desc) if owner
    -- If paired + pointed at car: Open proximity menu
    -- If right-click air/node: Remote menu for paired car (panic/locate from afar)
    -- Non-car object: Skip/no action
    on_use = function(itemstack, puncher, pointed_thing)
      local name = puncher:get_player_name()
      local meta = itemstack:get_meta()
      local paired_owner = meta:get("paired_owner") or ""
      local paired_id = meta:get("paired_id") or ""
      local key_name = itemstack:get_name()

      -- If pointed at an object (e.g., right-click entity like car)
      if pointed_thing and pointed_thing.type == "object" then
        local obj_ref = pointed_thing.ref           -- ObjectRef
        local luaent = obj_ref:get_luaentity()      -- LuaEntity (nil for non-entities like players)

        if luaent then                              -- It's a Lua entity (e.g., car)
          local ent_name = luaent.name or "unknown" -- e.g., "automobiles_lib:beetle"

          -- NEW: Check if it's a car entity (via name match)
          if not ent_name:match("automobiles_.") then
            smartlog(name, "Not a car—right-click air for remote menu or punch your car to pair.")
            return itemstack
          end

          -- Ensure car has owner/ID (like in on_punch)
          if luaent.owner == nil then
            luaent.owner = name
            smartlog(name, "Set as car owner.")
          end

          -- Owner check for pairing (only owner can pair)
          if name ~= luaent.owner and not minetest.check_player_privs(puncher, { server = true }) then
            minetest.chat_send_player(name, S("Only the car owner (@1) or an admin can pair keys to this car.", luaent.owner or "unknown"))
            return itemstack
          end

          -- Generate/register car_id if missing (fallback, like in on_punch)
          luaent.car_id = luaent.car_id or generate_car_id(name)
          if car_registry and not car_registry[luaent.car_id] then
            car_registry[luaent.car_id] = luaent
            minetest.log("action", "Registered new car ID '" .. luaent.car_id .. "' for user '" .. name .. "'")
          end

          -- NEW: Pairing logic via car_id (if unpaired)
          if paired_owner == "" then
            smartlog(name, "Pairing key to car (ID: " .. luaent.car_id .. ")...")

            -- Set meta with car_id (custom ID), color, etc.
            meta:set_string("paired_owner", luaent.owner)
            meta:set_string("paired_id", luaent.car_id) -- Key pairing via custom_id
            meta:set_string("car_color", luaent._color or "#FFFFFF")
            meta:set_string("key_type", key_name)
            local key_type = key_name:gsub("automobiles_lib:", "")
            local new_desc = S("Paired @1 Key for @2 (ID: @3)", key_type, luaent.owner, luaent.car_id)
            meta:set_string("description", new_desc)

            -- Apply changes to wielded item
            puncher:set_wielded_item(itemstack)

            -- Debug/Feedback
            minetest.chat_send_player(name,
              S("Key paired to your car (ID: @1)! Left-click air for remote menu.", luaent.car_id))
            minetest.log("action", name .. " paired key via car_id '" .. luaent.car_id .. "'")
            return itemstack -- Paired—exit early
          else
            -- If already paired, check if it matches this car (proximity menu)
            if paired_id == luaent.car_id then
              if automobiles_lib.show_key_formspec then
                automobiles_lib.show_key_formspec(name, luaent.car_id, key_name)
                smartlog(name, "Opened proximity menu for car ID: " .. luaent.car_id)
              else
                minetest.chat_send_player(name, "ERROR: show_key_formspec missing.")
              end
            else
              minetest.chat_send_player(name, S("Key already paired to another car (ID: @1). Unpair first.", paired_id))
            end
            return itemstack
          end
        else
          -- Pointed at non-entity object (e.g., player or dropped item)
          smartlog(name, "Can't pair to non-car object. Left-click your car or air for remote.")
          return itemstack
        end
      end -- End pointed_object handling

      -- Existing remote logic for air/node right-click (if paired)
      -- (No pairing here—pair via car right-click or punch)
      if paired_id == "" then
        minetest.chat_send_player(name, S("Unpaired key, left-click your car to pair it first."))
        return itemstack
      end

      local ent = automobiles_lib.get_car_by_id(paired_id)
      if not ent or not ent.object or not ent.car_id then
        minetest.chat_send_player(name,
          S("Paired car (ID: @1) not found—may be destroyed or unloaded. Re-pair/re-place/re-load or go near the car.",
            paired_id))
        return itemstack
      end

      if automobiles_lib.show_key_formspec then
        automobiles_lib.show_key_formspec(name, paired_id, key_name)
        smartlog(name, S("Opened remote menu for car ID: @1", paired_id))
      else
        minetest.chat_send_player(name, "ERROR: show_key_formspec missing—check formspecs.lua.")
      end

      return itemstack -- No consumption; preserves key
    end,
  })

  -- Conditional craft (requires Mesecons) - unchanged
  if minetest.get_modpath("mesecons_wireless") and minetest.get_modpath("mesecons_" .. (key.recipe[2]:match("(%w+):"))) then
    minetest.register_craft({
      type = "shapeless",
      output = "automobiles_lib:" .. key.name,
      recipe = key.recipe,
    })
  end
end



-- /unpair_key command - unchanged from before
minetest.register_chatcommand("unpair_key", {
  params = "<key_name>",
  description = "Unpair a key you are holding (owner only)",
  func = function(name, param)
    local player = minetest.get_player_by_name(name)
    if not player then return end
    local wielded = player:get_wielded_item()
    if wielded:get_name() ~= "automobiles_lib:" .. param then
      minetest.chat_send_player(name, "You must hold the specified key.")
      return
    end
    local meta = wielded:get_meta()
    if meta:get("paired_owner") ~= "" then
      meta:set_string("paired_owner", "")
      meta:set_string("car_color", "")
      local new_desc = "Unpaired Car Key" -- Reset desc if needed
      meta:set_string("description", new_desc)
      player:set_wielded_item(wielded)    -- Apply changes (no set_meta needed)
      minetest.chat_send_player(name, "Key unpaired.")
    else
      minetest.chat_send_player(name, "Key is not paired.")
    end
  end,
  privs = { interact = true },
})
