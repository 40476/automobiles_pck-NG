-- autodrive.lua - Version with pathfinding integration (fixed)

autodrive = {}

-- State - use weak table to avoid memory leaks
local vehicle_targets = setmetatable({}, {__mode = "k"})  -- weak keys
local vehicle_paths = setmetatable({}, {__mode = "k"})
local vehicle_path_index = setmetatable({}, {__mode = "k"})
local vehicle_last_path_time = setmetatable({}, {__mode = "k"})

-- Configuration
local MAX_SPEED = 10
local ACCEL_FACTOR = 2
local STEERING_GAIN = 0.1
MAX_STEERING_ANGLE = 15  -- degrees
local PATH_RECALC_INTERVAL = 1.0  -- Recalculate path every 5 seconds

-- Set target destination for a vehicle
function autodrive.set_target(self, pos)
    if not self or not self.object then return end
    
    vehicle_targets[self] = vector.round(pos)
    vehicle_paths[self] = nil  -- Clear any existing path
    vehicle_path_index[self] = nil
    vehicle_last_path_time[self] = 0
    
    if self.driver_name then
        minetest.chat_send_player(self.driver_name, "[Autodrive] Target set to " .. 
            minetest.pos_to_string(pos))
    end
end

-- Activate autodrive mode
function autodrive.activate(self)
    if not self.driver_name then
        return false
    end
    self._autodrive_active = true
    self._autodrive_accel = 0
    self._steering_angle = 0
    
    minetest.chat_send_player(self.driver_name, "[Autodrive] Autonomous drive activated.")
    return true
end

-- Deactivate autodrive mode
function autodrive.deactivate(self)
    self._autodrive_active = false
    self._autodrive_accel = 0
    self._steering_angle = 0
    
    if self.object then
        self.object:set_acceleration({x = 0, y = -9.8, z = 0})
    end
    
    -- Clear state
    vehicle_targets[self] = nil
    vehicle_paths[self] = nil
    vehicle_path_index[self] = nil
    vehicle_last_path_time[self] = nil
    
    if self.driver_name then
        minetest.chat_send_player(self.driver_name, "[Autodrive] Autonomous drive deactivated.")
    end
end

-- Simple steering towards target
local function steer_towards_target(self, target_pos)
    local obj = self.object
    if not obj then return 0 end
    
    local pos = obj:get_pos()
    local vel = obj:get_velocity()
    local speed = vector.length(vel)
    
    -- Direction to target
    local to_target = vector.subtract(target_pos, pos)
    to_target.y = 0
    local target_dir = vector.normalize(to_target)
    
    -- Current direction
    local current_dir
    if speed < 0.1 then
        current_dir = obj:get_look_dir()
    else
        current_dir = vector.normalize(vel)
    end
    current_dir.y = 0
    current_dir = vector.normalize(current_dir)
    
    -- Calculate steering angle
    local cross = vector.cross(current_dir, target_dir)
    local lateral_error = cross.y
    local Kp = 10.0  -- Proportional gain for steering
    local pid_steering = -Kp * lateral_error

    -- Clamp steering angle
    local MAX_STEERING_ANGLE = 15  -- degrees
    pid_steering = math.max(-MAX_STEERING_ANGLE, math.min(MAX_STEERING_ANGLE, pid_steering))

    return pid_steering

end

-- Simple obstacle avoidance
local function avoid_obstacles(self)
    local obj = self.object
    if not obj then return 0, 0 end  -- steering_correction, speed_mod
    
    local pos = obj:get_pos()
    local vel = obj:get_velocity()
    local speed = vector.length(vel)
    
    -- Current direction
    local current_dir
    if speed < 0.1 then
        current_dir = obj:get_look_dir()
    else
        current_dir = vector.normalize(vel)
    end
    current_dir.y = 0
    
    -- Scan forward
    local forward_clear = 10
    for i = 1, 10 do
        local scan_pos = vector.add(pos, vector.multiply(current_dir, i))
        scan_pos.y = pos.y
        local node = minetest.get_node(scan_pos)
        if minetest.registered_nodes[node.name] and 
           minetest.registered_nodes[node.name].walkable then
            forward_clear = i - 1
            break
        end
    end
    
    -- Scan sides
    local left_dir = {x = -current_dir.z, y = 0, z = current_dir.x}
    local right_dir = {x = current_dir.z, y = 0, z = -current_dir.x}
    
    local left_clear = 5
    local right_clear = 5
    
    for i = 1, 5 do
        -- Left scan
        local left_pos = vector.add(pos, vector.multiply(left_dir, i))
        left_pos.y = pos.y
        local left_node = minetest.get_node(left_pos)
        if minetest.registered_nodes[left_node.name] and 
           minetest.registered_nodes[left_node.name].walkable then
            left_clear = i - 1
        end
        
        -- Right scan
        local right_pos = vector.add(pos, vector.multiply(right_dir, i))
        right_pos.y = pos.y
        local right_node = minetest.get_node(right_pos)
        if minetest.registered_nodes[right_node.name] and 
           minetest.registered_nodes[right_node.name].walkable then
            right_clear = i - 1
        end
    end
    
    -- Calculate steering correction
    local clearance_diff = left_clear - right_clear
    local steering_correction = clearance_diff * 2  -- Simple steering gain
    
    -- Speed modification based on forward clearance
    local speed_mod = 1.0
    if forward_clear < 3 then
        speed_mod = 0.3  -- Slow down significantly
    elseif forward_clear < 6 then
        speed_mod = 0.7  -- Moderate slowdown
    end
    
    return steering_correction, speed_mod
end

-- Get next waypoint from path
local function get_next_waypoint(self, pos, target_position)
    local path = vehicle_paths[self]
    local path_idx = vehicle_path_index[self] or 1
    
    if not path or #path == 0 then
        return target_position
    end
    
    -- Find closest waypoint that's ahead
    local closest_dist = math.huge
    local closest_idx = path_idx
    
    for i = path_idx, math.min(path_idx + 5, #path) do
        local waypoint = path[i]
        local dist = vector.distance(pos, waypoint)
        if dist < closest_dist then
            closest_dist = dist
            closest_idx = i
        end
    end
    
    -- Update path index to closest waypoint
    vehicle_path_index[self] = closest_idx
    
    -- Return next waypoint, or target if we're at the end
    if closest_idx < #path then
        return path[closest_idx + 1]
    else
        return target_position
    end
end

-- Main update function
function autodrive.update(self, dtime)
    if not self._autodrive_active then 
        return 
    end

    local obj = self.object
    if not obj then return end
    
    local target_position = vehicle_targets[self]
    if not target_position then 
        obj:set_acceleration({x = 0, y = -9.8, z = 0})
        self._steering_angle = 0
        return 
    end
    
    local pos = obj:get_pos()
    local distance_to_target = vector.distance(pos, target_position)
    
    -- Check if we've reached the target
    if distance_to_target < 3.0 then
        obj:set_acceleration({x = 0, y = -9.8, z = 0})
        self._steering_angle = 0
        vehicle_targets[self] = nil
        vehicle_paths[self] = nil
        vehicle_path_index[self] = nil
        vehicle_last_path_time[self] = nil
        
        if self.driver_name then
            minetest.chat_send_player(self.driver_name, "[Autodrive] Target reached!")
        end
        return
    end
    
    -- Recalculate path periodically or if no path exists
    local last_path_time = vehicle_last_path_time[self] or 0
    if (not vehicle_paths[self] or (minetest.get_gametime() - last_path_time) > PATH_RECALC_INTERVAL) and pathfinder then
        vehicle_last_path_time[self] = minetest.get_gametime()
        
        -- Prepare entity info for pathfinder
        local entity_info = {
            collisionbox = self.collisionbox or {-0.5, 0, -0.5, 0.5, 1, 0.5},
            fear_height = self.fear_height or 3,
            jump_height = self.jump_height or 1
        }
        
        -- Calculate path (this might take some time)
        local path = pathfinder.find_path(pos, target_position, entity_info, dtime)
        if path and #path > 1 then
            vehicle_paths[self] = path
            vehicle_path_index[self] = 1
            
            if self.driver_name then
                minetest.chat_send_player(self.driver_name, "[Autodrive] Path calculated with " .. #path .. " waypoints")
            end
        else
            -- Fallback to direct navigation if pathfinding fails
            vehicle_paths[self] = nil
            vehicle_path_index[self] = nil
            
            if self.driver_name then
                minetest.chat_send_player(self.driver_name, "[Autodrive] Pathfinding failed, using direct navigation")
            end
        end
    end
    
    -- Get current target (either next waypoint or final target)
    local current_target = target_position
    if vehicle_paths[self] then
        current_target = get_next_waypoint(self, pos, target_position)
    end
    
    -- Get steering towards target
    local target_steering = steer_towards_target(self, current_target)
    
    -- Get obstacle avoidance
    local obstacle_steering, speed_mod = avoid_obstacles(self)
    
    -- Check if target is behind us
    local to_target = vector.subtract(current_target or pos, pos)
    to_target.y = 0
    local target_dir = vector.normalize(to_target)
    local target_speed = MAX_SPEED * speed_mod
    local dot = 0
    if current_dir and target_dir then
        dot = vector.dot(current_dir, target_dir)
    end


    -- If target is behind, increase steering and reduce speed
    if dot < 0.3 then  -- target is significantly behind
        target_steering = target_steering * 1.5  -- turn harder
        target_speed = target_speed * 0.5        -- slow down
    end

    -- If angle to target is large, slow down more
    local angle_to_target = math.abs(target_steering)
    if angle_to_target > 45 then
        target_speed = target_speed * 0.5
    elseif angle_to_target > 20 then
        target_speed = target_speed * 0.8
    end


    -- Combine steering
    -- Damping and proportional blending
    local damping_factor = 0.5
    local deviation = math.abs(target_steering) / MAX_STEERING_ANGLE
    local proportional_gain = math.min(1.0, deviation * 2)

    local blended_steering = target_steering * proportional_gain * 0.7 + obstacle_steering * STEERING_GAIN
    self._steering_angle = self._steering_angle * damping_factor + blended_steering * (1 - damping_factor)

    
    -- Calculate acceleration
    
    
    -- Reduce speed when close to target
    if distance_to_target < 15.0 then
        target_speed = target_speed * (distance_to_target / 15.0)
    end
    
    local vel = obj:get_velocity()
    local speed = vector.length(vel)
    local current_dir
    if speed < 0.1 then
        current_dir = obj:get_look_dir()
    else
        current_dir = vector.normalize(vel)
    end
    current_dir.y = 0
    
    if speed < target_speed then
        self._autodrive_accel = ACCEL_FACTOR
    else
        self._autodrive_accel = 0
    end
    
    -- Apply acceleration
    local accel = vector.multiply(current_dir, self._autodrive_accel)
    accel.y = -9.8  -- Always apply gravity
    obj:set_acceleration(accel)
    
    -- Debug output (remove this in production)
    if self.driver_name and math.random() < 0.05 then  -- Every ~1 second
        minetest.chat_send_player(self.driver_name, 
            string.format("[Autodrive] Dist: %.1f, Speed: %.1f, Steering: %.1f", 
            distance_to_target, speed, self._steering_angle))
    end
end

return autodrive