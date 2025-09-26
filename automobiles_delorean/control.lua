-- delorean control.lua with autodrive integration

function delorean.control(self, dtime, hull_direction, longit_speed, longit_drag, later_drag, accel, max_acc_factor,
                          max_speed, steering_limit, steering_speed)

  local player = minetest.get_player_by_name(self.driver_name)
  local ctrl = player:get_player_control()
  acc = self._autodrive_accel or 0
  -- minetest.chat_send_player(self.driver_name, 'acc: ' .. acc .. " auto accel: " .. self._autodrive_accel)
  self._last_time_command = self._last_time_command + dtime
  if self._last_time_command > 1 then self._last_time_command = 1 end

  local player = minetest.get_player_by_name(self.driver_name)
  local retval_accel = accel
  local stop = false

  -- Handle autodrive emergency stop
  if self._autodrive_emergency_stop then
    self.object:set_velocity(vector.new(0, self.object:get_velocity().y, 0))
    self._autodrive_emergency_stop = false
    stop = true
  end

  -- player control (or autodrive control)
  -- if player then


  -- Manual control
  if self._energy > 0 then
    if longit_speed < max_speed and ctrl.up then
      acc = automobiles_lib.check_road_is_ok(self.object, max_acc_factor)
      if acc > 1 and acc < max_acc_factor and longit_speed > 0 then
        acc = -1
      end
    end

    if not self._is_flying or self._is_flying == 0 then
      if ctrl.sneak and longit_speed <= 1.0 and longit_speed > -1.0 then
        acc = -2
      end
    end
  end

  if ctrl.down then
    if not self._is_flying or self._is_flying == 0 then
      if longit_speed > 0 then
        acc = -5
      end
      if longit_speed < 0 then
        acc = 5
        if (longit_speed + acc) > 0 then
          acc = longit_speed * -1
        end
      end
      if math.abs(longit_speed) < 0.2 then
        stop = true
      end
    else
      acc = -5
    end
  end

  -- Manual steering
  if self._yaw_by_mouse == true then
    local rot_y = math.deg(player:get_look_horizontal())
    self._steering_angle = automobiles_lib.set_yaw_by_mouse(self, rot_y, steering_limit)
  else
    if ctrl.right then
      self._steering_angle = math.max((self._steering_angle or 0) - steering_speed * dtime, -steering_limit)
    elseif ctrl.left then
      self._steering_angle = math.min((self._steering_angle or 0) + steering_speed * dtime, steering_limit)
    else
      -- Center steering
      if longit_speed > 0 then
        local factor = 1
        if (self._steering_angle or 0) > 0 then factor = -1 end
        local correction = (steering_limit * (longit_speed / 75)) * factor
        local before_correction = (self._steering_angle or 0)
        self._steering_angle = (self._steering_angle or 0) + correction
        if math.sign(before_correction) ~= math.sign(self._steering_angle or 0) then
          self._steering_angle = 0
        end
      end
    end
  end


  if acc then
    retval_accel = vector.add(accel, vector.multiply(hull_direction, acc))
  end

  -- -- Apply curve deceleration for manual control only (autodrive handles its own)
  -- if not using_autodrive then
  --   local angle_factor = (self._steering_angle or 0) / 60
  --   if angle_factor < 0 then angle_factor = angle_factor * -1 end
  --   local deacc_on_curve = longit_speed * angle_factor
  --   deacc_on_curve = deacc_on_curve * -1
  --   if deacc_on_curve then
  --     retval_accel = vector.add(retval_accel, vector.multiply(hull_direction, deacc_on_curve))
  --   end
  -- end
  -- end

  return retval_accel, stop
end
