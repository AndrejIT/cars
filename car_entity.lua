local car_entity = {
    hp_max = 80,
	--physical = true, -- let's see if i can deal with this
    physical = false, -- nope
	collisionbox = {-0.5, -0.1, -0.5, 0.5, 0.8, 0.5},
    --collisionbox = {-0.6, 0.0, -1.85, 1.4, 1.5, 1.25},
	visual = "mesh",
	--mesh = "cars_car.b3d",
    mesh = "car_001.obj",
	visual_size = {x=1, y=1},
	--textures = {"cars_car.png"},
	textures = {"textur_grey.png"},
    --seats = {false, false},
    --automatic_rotate = true,

    fuel = 0,

	driver = nil,
    passenger = nil,
	punched = false, -- used to re-send velocity and position
    punch_direction = true,
    control_left = nil,
    control_right = nil,
    control_up = nil,
    control_turbo = nil,
    control_count = 0,

	attached_items = {},

    old_pos = nil,	--rounded
    next_pos = nil,	--rounded
    old_direction = nil,
    full_stop = false,  --when car stopped and dont hawe any reason to move

    -- sound refresh interval = 1.0sec
    rail_sound = function(self, dtime)
    	if not self.sound_ttl then
    		self.sound_ttl = 1.0
    		return
    	elseif self.sound_ttl > 0 then
    		self.sound_ttl = self.sound_ttl - dtime
    		return
    	end
    	self.sound_ttl = 1.0
    	if self.sound_handle then
    		local handle = self.sound_handle
    		self.sound_handle = nil
    		minetest.after(0.2, minetest.sound_stop, handle)
    	end
    	local vel = self.object:getvelocity()
    	local speed = vector.length(vel)
    	if speed > 3 then
    		self.sound_handle = minetest.sound_play(
    			"cars_car_moving", {
    			object = self.object,
    			gain = (speed / cars.speed_max) / 2,
    			loop = true,
    		})
    	end
    end,

    --set yaw using vector
    set_yaw = function(self, v)
        if v.x == 0 and v.z == 0 then
            return  --keep old jaw
        end

        local yaw = vector_yaw(v)

        self.object:setyaw(yaw)
    end,

    --get yaw as a vector
    get_yaw = function(self)
        local yaw = self.object:getyaw()

        local v = yaw_vector(yaw)

        v = vector.normalize(v)
        return v
    end,

    --set velocity
    set_velocity = function(self, v)
        if not v then
            v = {x=0, y=0, z=0}
        end
        self.object:setvelocity(v)
    end,

    --align car position on railroad
    precize_on_rail = function(self, pos, tolerance)
        local v = self.object:getvelocity()
        local aligned_pos = table.copy(pos)
    	if self.old_direction.x == 0 and math.abs(self.old_pos.x-pos.x)>(tolerance+1) then
            aligned_pos.x = self.old_pos.x
    		self.object:setpos(aligned_pos)
    	elseif self.old_direction.z == 0 and math.abs(self.old_pos.z-pos.z)>(tolerance+1) then
            aligned_pos.z = self.old_pos.z
    		self.object:setpos(aligned_pos)
    	elseif self.old_direction.y == 0 and math.abs(self.old_pos.y-pos.y)>tolerance then
            aligned_pos.y = self.old_pos.y
    		self.object:setpos(aligned_pos)
    	end
    end,

    -- rounded to 1 direction vector betvin start and end positions
    precize_direction = function(self, pos1, pos2)
        local dir = {x=0, y=0, z=0}
        if pos1.x == pos2.x then
            dir.z = math.sign(pos2.z - pos1.z)
        elseif pos1.z == pos2.z then
            dir.x = math.sign(pos2.x - pos1.x)
        elseif math.abs(pos2.x - pos1.x) < math.abs(pos2.z - pos1.z) then
            dir.z = math.sign(pos2.z - pos1.z)
        else
            dir.x = math.sign(pos2.x - pos1.x)
        end

        if math.abs(pos2.y - pos1.y) > 0 then
            dir.y = math.sign(pos2.y - pos1.y)
        end
        return dir
    end,

    --position, relative to
    --x-FRONT/BACK, z-LEFT/RIGHT
    get_pos_relative = function(self, rel_pos, position, direction)
        local pos = position
        if pos == nil then
            pos = self.object:getpos()
        end

        if not rel_pos then
            return pos
        elseif rel_pos.x == 0 and rel_pos.z == 0 then
            return {x=pos.x, y=pos.y+rel_pos.y, z=pos.z}
        end

        local dir = direction
        if dir == nil then
            local yaw = self.object:getyaw()

            dir = {x=0, y=0, z=0}

            yaw = yaw + math.pi/2
            dir.x = math.cos(yaw)
            dir.z = math.sin(yaw)

            dir = vector.normalize(dir)
        end

        if --NORD
            dir.x > 0 and
            dir.z <= math.abs(dir.x)
        then
            return {x=pos.x+rel_pos.x, y=pos.y+rel_pos.y, z=pos.z+rel_pos.z}
        elseif --EAST
            dir.z < 0 and
            dir.x <= math.abs(dir.z)
        then
            return {x=pos.x+rel_pos.z, y=pos.y+rel_pos.y, z=pos.z-rel_pos.x}
        elseif --WEST
            dir.z > 0 and
            dir.x <= math.abs(dir.z)
        then
            return {x=pos.x-rel_pos.z, y=pos.y+rel_pos.y, z=pos.z+rel_pos.x}
        elseif --SOUTH
            dir.x < 0 and
            dir.z <= math.abs(dir.x)
        then
            return {x=pos.x-rel_pos.x, y=pos.y+rel_pos.y, z=pos.z-rel_pos.z}
        end

        minetest.log("warning", "Object direction not set")
        return pos  --should not be reached
    end,

    --check if position can be used as road
    check_road = function(self, pos)
        local r0 = minetest.get_node({x=pos.x, y=pos.y-1, z=pos.z}).name
        local r1 = minetest.get_node(pos).name
        local r2 = minetest.get_node({x=pos.x, y=pos.y+1, z=pos.z}).name
        if
            r0 == 'asphalt:asphalt' or
            minetest.get_item_group(r0, "cracky") > 0 or
            minetest.get_item_group(r0, "choppy") > 0 or
            minetest.get_item_group(r0, "crumbly") > 0
        then
            if
                r1 == 'ignore' or
                minetest.get_item_group(r1, "cracky") > 0 or
                minetest.get_item_group(r2, "cracky") > 0 or
                minetest.get_item_group(r1, "crumbly") > 0 or
                minetest.get_item_group(r2, "crumbly") > 0 or
                minetest.get_item_group(r1, "choppy") > 0 or
                minetest.get_item_group(r2, "choppy") > 0 or
                minetest.get_item_group(r1, "water") > 0 or
                minetest.get_item_group(r1, "lava") > 0
            then
                return false
            else
                return true
            end
        else
            return false
        end
    end,

    --calculate next acceptable car position
    get_next_rail_pos = function(self, pos, dir)
        local n_pos = nil
        if self.control_left then
            self.control_count = self.control_count + 1
            if self:check_road(self:get_pos_relative({x=0, y=0, z=1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=0, z=1}, pos, dir);    --left
            elseif self:check_road(self:get_pos_relative({x=0, y=-1, z=1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=-1, z=1}, pos, dir);    --left down
            elseif self:check_road(self:get_pos_relative({x=0, y=1, z=1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=1, z=1}, pos, dir);    --left up
            elseif self:check_road(self:get_pos_relative({x=1, y=1, z=0}, pos, dir)) then
                n_pos = self:get_pos_relative({x=1, y=0, z=0}, pos, dir);     --front
            elseif self:check_road(self:get_pos_relative({x=1, y=1, z=0}, pos, dir)) then
                n_pos = self:get_pos_relative({x=1, y=1, z=0}, pos, dir);     --up
            elseif self:check_road(self:get_pos_relative({x=1, y=-1, z=0}, pos, dir)) then
                n_pos = self:get_pos_relative({x=1, y=-1, z=0}, pos, dir);    --down
            elseif self:check_road(self:get_pos_relative({x=0, y=0, z=-1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=0, z=-1}, pos, dir);    --right
            elseif self:check_road(self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir);    --right down
            elseif self:check_road(self:get_pos_relative({x=0, y=1, z=-1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=1, z=-1}, pos, dir);    --right up
            else
                n_pos = nil
            end
        elseif self.control_right then
            self.control_count = self.control_count + 1
            if self:check_road(self:get_pos_relative({x=0, y=0, z=-1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=0, z=-1}, pos, dir);    --right
            elseif self:check_road(self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir);    --right down
            elseif self:check_road(self:get_pos_relative({x=0, y=1, z=-1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=1, z=-1}, pos, dir);    --right up
            elseif self:check_road(self:get_pos_relative({x=1, y=0, z=0}, pos, dir)) then
                n_pos = self:get_pos_relative({x=1, y=0, z=0}, pos, dir);     --front
            elseif self:check_road(self:get_pos_relative({x=1, y=1, z=0}, pos, dir)) then
                n_pos = self:get_pos_relative({x=1, y=1, z=0}, pos, dir);     --up
            elseif self:check_road(self:get_pos_relative({x=1, y=-1, z=0}, pos, dir)) then
                n_pos = self:get_pos_relative({x=1, y=-1, z=0}, pos, dir);    --down
            elseif self:check_road(self:get_pos_relative({x=0, y=0, z=1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=0, z=1}, pos, dir);    --left
            elseif self:check_road(self:get_pos_relative({x=0, y=-1, z=1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=-1, z=1}, pos, dir);    --left down
            elseif self:check_road(self:get_pos_relative({x=0, y=1, z=1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=1, z=1}, pos, dir);    --left up
            else
                n_pos = nil
            end
        -- elseif self.control_up then
        --     if self:check_road(self:get_pos_relative({x=1, y=0, z=0}, pos, dir)) then
        --         n_pos = self:get_pos_relative({x=1, y=0, z=0}, pos, dir);     --front
        --     elseif self:check_road(self:get_pos_relative({x=1, y=1, z=0}, pos, dir)) then
        --         n_pos = self:get_pos_relative({x=1, y=1, z=0}, pos, dir);     --up
        --     elseif self:check_road(self:get_pos_relative({x=1, y=-1, z=0}, pos, dir)) then
        --         n_pos = self:get_pos_relative({x=1, y=-1, z=0}, pos, dir);    --down
        --     elseif self:check_road(self:get_pos_relative({x=0, y=0, z=1}, pos, dir)) then
        --         n_pos = self:get_pos_relative({x=0, y=0, z=1}, pos, dir);    --left
        --     elseif self:check_road(self:get_pos_relative({x=0, y=0, z=-1}, pos, dir)) then
        --         n_pos = self:get_pos_relative({x=0, y=0, z=-1}, pos, dir);    --right
        --     elseif self:check_road(self:get_pos_relative({x=0, y=-1, z=1}, pos, dir)) then
        --         n_pos = self:get_pos_relative({x=0, y=-1, z=1}, pos, dir);    --left down
        --     elseif self:check_road(self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir)) then
        --         n_pos = self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir);    --right down
        --     elseif self:check_road(self:get_pos_relative({x=0, y=1, z=1}, pos, dir)) then
        --         n_pos = self:get_pos_relative({x=0, y=1, z=1}, pos, dir);    --left up
        --     elseif self:check_road(self:get_pos_relative({x=0, y=1, z=-1}, pos, dir)) then
        --         n_pos = self:get_pos_relative({x=0, y=1, z=-1}, pos, dir);    --right up
        --     else
        --         n_pos = nil
        --     end
        else
            if self:check_road(self:get_pos_relative({x=1, y=0, z=0}, pos, dir)) then
                n_pos = self:get_pos_relative({x=1, y=0, z=0}, pos, dir);     --front
            elseif self:check_road(self:get_pos_relative({x=1, y=1, z=0}, pos, dir)) then
                n_pos = self:get_pos_relative({x=1, y=1, z=0}, pos, dir);     --up
            elseif self:check_road(self:get_pos_relative({x=1, y=-1, z=0}, pos, dir)) then
                n_pos = self:get_pos_relative({x=1, y=-1, z=0}, pos, dir);    --down
            elseif self:check_road(self:get_pos_relative({x=0, y=0, z=1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=0, z=1}, pos, dir);    --left
            elseif self:check_road(self:get_pos_relative({x=0, y=0, z=-1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=0, z=-1}, pos, dir);    --right
            elseif self:check_road(self:get_pos_relative({x=0, y=-1, z=1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=-1, z=1}, pos, dir);    --left down
            elseif self:check_road(self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=-1, z=-1}, pos, dir);    --right down
            elseif self:check_road(self:get_pos_relative({x=0, y=1, z=1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=1, z=1}, pos, dir);    --left up
            elseif self:check_road(self:get_pos_relative({x=0, y=1, z=-1}, pos, dir)) then
                n_pos = self:get_pos_relative({x=0, y=1, z=-1}, pos, dir);    --right up
            else
                n_pos = nil
            end
        end
        if n_pos then
            n_pos = vector.round(n_pos)
        end
        return n_pos
    end,

    on_activate = function(self, staticdata, dtime_s)
        -- self.object:set_armor_groups({immortal=1})
        self.object:set_armor_groups({fleshy=40, snappy=60, choppy=80})

        --decrease speed after car is left unattended
        self.object:setvelocity(vector.multiply(self.object:getvelocity(), 0.5))

        local pos = self.object:getpos()
        local d = self:get_yaw()

        self.old_pos = vector.round(pos)
        local dir = self:get_yaw()
        if self.old_direction then
            dir = table.copy(self.old_direction)
        end

        --self.old_direction = self:get_yaw()

        --strict direction
        dir.y = 0
        if math.abs(dir.x) > math.abs(dir.z) then
            dir.z = 0
        else
            dir.x = 0
        end
        self.old_direction = vector.round(dir)
    end,

    on_step = function(self, dtime)
        local pos = self.object:getpos()
        local p = vector.round(pos)
        local v = self.object:getvelocity()
        local s = vector.length(v)

        -- Get player controls
        if self.driver then
            player = minetest.get_player_by_name(self.driver)
            if player then
                ctrl = player:get_player_control()

                if ctrl and ctrl.right then
                    if self.control_count > 0 then
                        self.control_left = nil
                        self.control_count = 0
                    else
                        self.control_left = nil
                        self.control_right = true
                        self.control_up = nil
                        self.control_turbo = nil
                    end
                elseif ctrl and ctrl.left then
                    if self.control_count > 0 then
                        self.control_right = nil
                        self.control_count = 0
                    else
                        self.control_left = true
                        self.control_right = nil
                        self.control_up = nil
                        self.control_turbo = nil
                    end
                elseif ctrl and ctrl.sneak and ctrl.up then
                    if self.fuel-1 >= 0 and (s + 2) <= cars.speed_max_turbo then
                        s = s + 2
                        if s > 4 then
                            self.fuel = self.fuel - 1
                        end
                    end
                    self.control_left = nil
                    self.control_right = nil
                    self.control_up = true
                    self.control_turbo = true
                elseif ctrl and ctrl.up then
                    if self.fuel-0.5 >= 0 and (s + 1) <= cars.speed_max then
                        s = s + 1
                        if s > 4 then
                            self.fuel = self.fuel - 0.5
                        end
                    end
                    self.control_left = nil
                    self.control_right = nil
                    self.control_up = true
                else
                    self.control_left = nil
                    self.control_right = nil
                    self.control_up = nil
                end

                if ctrl and ctrl.down then
                    if (s - 2) >= 0 then
                        s = s - 2
                    end
                end
            end
        end


        if self.full_stop then
            -- when punch or mesecons
            if self.punched and self.punch_direction then
                self.full_stop = false
                --handle punch
                if (s + 1) <= cars.punch_speed_max then
                    s = s + 1
                    local dir = table.copy(self.punch_direction)
                    dir.y = 0
                    -- --strict direction
                    -- if math.abs(dir.x) > math.abs(dir.z) then
                    --     dir.z = 0
                    -- else
                    --     dir.x = 0
                    -- end
                    dir = vector.normalize(dir)
                    -- self.old_direction = vector.round(dir)
                    self.punched = nil

                    self.old_pos = table.copy(p)
                    self.next_pos = self:get_next_rail_pos(p, self.old_direction)

                    if self.next_pos then
                        --set new car object parameters
                        v = vector.multiply(vector.normalize(self.old_direction), s)
                        self:set_velocity(v)
                        self:set_yaw(self.old_direction)
                    end
                else
                    self.punched = nil
                end
            end
        elseif s < 0.3 then
            -- when stop is temporary
            -- also when car is first placed
            local node = minetest.get_node({x=p.x, y=p.y-1, z=p.z})
            -- uphill - invert old direction
            if self.old_direction.y == 1 then
                self.old_direction.x = -self.old_direction.x
                self.old_direction.z = -self.old_direction.z
                self.old_direction.y = -1
                s = s + 0.5 -- downhill
            end

            self.old_pos = table.copy(p)
            self.next_pos = self:get_next_rail_pos(p, self.old_direction)

            if self.next_pos then
                self.old_direction = self:precize_direction(self.old_pos, self.next_pos)
                --check rail and handle energy loss/increase
                if node.name == "asphalt:asphalt" then
                    s = s - 0.01
                else
                    s = s - 0.1 --something else
                end

                -- car will not move anymore
                if s < 0.3 then
                    s = 0
                    self.next_pos = nil
                    self.full_stop = true
                end
            else
                s = 0
                self.full_stop = true
            end

            --set new car object parameters
            v = vector.multiply(vector.normalize(self.old_direction), s)
            self:set_velocity(v)
            self:set_yaw(self.old_direction)

        elseif self.next_pos == nil or
            math.abs(self.old_pos.x - pos.x) > 0.5 or
            math.abs(self.old_pos.z - pos.z) > 0.5
        then
            -- when car reached next rail
            local node = minetest.get_node({x=p.x, y=p.y-1, z=p.z})
            self:precize_on_rail(pos, 0.2)

            --calculate where car will go next
            if node.name == "ignore" then
                --map not loaded yet
                self.next_pos = nil
                s = s * 0.5
            elseif self:check_road(p) and
                (math.abs(self.old_pos.x - pos.x) > 1.5 or
                math.abs(self.old_pos.z - pos.z) > 1.5)
            then
                --car went too far, accept new road
                self.old_pos = table.copy(p)
                self.next_pos = self:get_next_rail_pos(p, self.old_direction)
                s = s * 0.9
            elseif (math.abs(self.old_pos.x - pos.x) > 1.5 or
                math.abs(self.old_pos.z - pos.z) > 1.5)
            then
                --car went too far, return to old road
                if self.next_pos then
                    local nextnext_pos = self:get_next_rail_pos(self.next_pos, self.old_direction)
                    if nextnext_pos == nil then
                        --dead end, stop car
                        self.old_pos = table.copy(self.next_pos)
                        self.full_stop = true
                        self.next_pos = nil
                        self.object:setpos(self.old_pos)
                        s = 0
                    else
                        --continue from last rail
                        local dir = self:precize_direction(self.next_pos, nextnext_pos)
                        self.old_pos = table.copy(nextnext_pos)
                        self.object:setpos(nextnext_pos)
                        self.next_pos = self:get_next_rail_pos(nextnext_pos, dir)
                    end
                end
                s = s * 0.9
            elseif self:check_road(p) and self.next_pos and
                (math.abs(self.old_pos.x - pos.x) > 0.5 or
                math.abs(self.old_pos.z - pos.z) > 0.5)
            then
                --on next rail
                self.old_pos = table.copy(p)
                self.next_pos = self:get_next_rail_pos(p, self.old_direction)

                if self.next_pos == nil then
                    --dead end, stop car
                    self.full_stop = true
                    self.next_pos = nil
                    self.object:setpos(self.old_pos)
                    s = 0
                end
            elseif self:check_road(p) and self.next_pos == nil then
                --on rail position
                self.old_pos = table.copy(p)
                self.next_pos = self:get_next_rail_pos(p, self.old_direction)

                if self.next_pos == nil then
                    --dead end, stop car
                    self.full_stop = true
                    self.next_pos = nil
                    self.object:setpos(self.old_pos)
                    s = 0
                end
            end

            self.control_left = nil
            self.control_right = nil
            self.control_up = nil

            --calculate next car direction
            if self.old_pos ~=nil and self.next_pos ~= nil then
                local dir = self:precize_direction(self.old_pos, self.next_pos)
                local direction_changes = false

                -- direction changes
                if dir.x ~= self.old_direction.x or dir.z ~= self.old_direction.z or dir.y ~= self.old_direction.y then
                    --do not flip!
                    if dir.x * self.old_direction.x ~= -1 and dir.z * self.old_direction.z ~= -1 then
                        direction_changes = true
                    end
                end

                -- new direction
                if direction_changes then
                    self.old_direction = table.copy(dir)
                end

                -- more energy loss on turns
                if direction_changes then
                    s = s - 0.2
                end
            end

            --handle downhill/uphill energy
            if self.next_pos ~= nil then
                if self.next_pos.y < self.old_pos.y then
                    s = s + 0.5 -- downhill
                elseif self.next_pos.y > self.old_pos.y then
                    s = s - 0.5 -- uphill
                end
            end

            --check rail and handle energy loss/increase
            if self.next_pos ~= nil then
                if node.name == "asphalt:asphalt" then
                    s = s - 0.01
                else
                    s = s - 0.1 --something else
                end
                -- loss energy on skipped blocks
                s = s - 0.01 * vector.distance(self.next_pos, self.old_pos)
            end

            --mesecons support?
            -- --local acceleration = minetest.get_item_group(node.name, "acceleration")
            -- local acceleration = tonumber(minetest.get_meta(p):get_string("car_acceleration"))--original PilzAdam version
            -- if acceleration > 0 or acceleration < 0 then
            --     s = s + acceleration     --powerrail
            -- end

            --handle punch
            if self.punched and self.punch_direction then
                if (s + 1) <= cars.punch_speed_max then
                    s = s + 1
                else
                    self.punched = nil
                end
            end

            --limit speed
            if self.control_turbo then
                if s > cars.speed_max_turbo then
                    s = cars.speed_max_turbo
                end
            elseif s > cars.speed_max then
                s = cars.speed_max
            elseif s < 0 then
                s = 0
            end

            -- car will not move anymore
            if s < 0.3 then
                s = 0
                self.next_pos = nil
                -- downhil/uphill and powerrail prevent stop
                if
                    self.old_direction.y == 0
                then
                    self.full_stop = true
                end
            end

            --set new car object parameters
            v = vector.multiply(vector.normalize(self.old_direction), s)
            self:set_velocity(v)

            self:set_yaw(self.old_direction)
        end

        --animation for uphill/downhill
        if self.old_direction.y < 0 then
            self.object:set_animation({x=1, y=1}, 1, 0)
        elseif self.old_direction.y > 0  then
            self.object:set_animation({x=2, y=2}, 1, 0)
        else
            self.object:set_animation({x=0, y=0}, 1, 0)
        end

        --handle sound
        self:rail_sound(dtime)
    end,

    on_rightclick = function(self, clicker)
    	if not clicker or not clicker:is_player() then
    		return
    	end
    	local player_name = clicker:get_player_name()
    	if self.driver and player_name == self.driver then
    		self.driver = nil
    		cars:manage_attachment(clicker, nil)
        elseif self.passenger and player_name == self.passenger then
    		self.passenger = nil
    		cars:manage_attachment(clicker, nil)
    	elseif not self.driver then
    		self.driver = player_name
    		cars:manage_attachment(clicker, self.object)
    	elseif not self.passenger then
    		self.passenger = player_name
    		cars:manage_attachment(clicker, self.object, 2)
    	end
    end,

    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, direction)
    	if not puncher or not puncher:is_player() then
            -- Punched by non-player
    		self.punched = true
            self.punch_direction = direction
        elseif puncher:get_player_control().sneak then
            -- Player digs car by sneak-punch
            if self.driver == nil or puncher:get_player_name() == self.driver then
        		if self.sound_handle then
        			minetest.sound_stop(self.sound_handle)
        		end
        		-- Detach driver and items
        		if self.driver then
        			if self.old_pos then
        				self.object:setpos(self.old_pos)
        			end
        			local player = minetest.get_player_by_name(self.driver)
        			cars:manage_attachment(player, nil)
        		end
                if self.passenger then
        			local player = minetest.get_player_by_name(self.passenger)
        			cars:manage_attachment(player, nil)
        		end
        		for _,obj_ in ipairs(self.attached_items) do
        			if obj_ then
        				obj_:set_detach()
        			end
        		end
        		-- Pick up car
        		local inv = puncher:get_inventory()
        		if not (creative and creative.is_enabled_for
        				and creative.is_enabled_for(puncher:get_player_name()))
        				or not inv:contains_item("main", "cars:car") then
        			local leftover = inv:add_item("main", cars.car_to_item(self))
        			-- If no room in inventory add a replacement car to the world
        			if not leftover:is_empty() then
        				minetest.add_item(self.object:getpos(), leftover)
        			end
        		end
        		self.object:remove()
            end
        else
            -- simple tool wear
            if puncher and puncher:is_player() and puncher:get_wielded_item() then
                local tool=puncher:get_wielded_item()
                tool:add_wear(100)
                puncher:set_wielded_item(tool)
            end
            -- car is not immortal anymore, so handle when it is destroyed
            minetest.after(0,
                function(self)
                    if self.object:get_hp() <= 0 then
                        -- to stop soun when car unloads, is destroyed or is picked up
                        if self.sound_handle then
                            minetest.sound_stop(self.sound_handle)
                        end
                        -- Detach driver and items
                        if self.driver then
                            if self.old_pos then
                                self.object:setpos(self.old_pos)
                            end
                            local player = minetest.get_player_by_name(self.driver)
                            cars:manage_attachment(player, nil)
                        end
                        if self.passenger then
                            local player = minetest.get_player_by_name(self.passenger)
                            cars:manage_attachment(player, nil)
                        end
                        for _,obj_ in ipairs(self.attached_items) do
                            if obj_ then
                                obj_:set_detach()
                            end
                        end
                    end
                end,
            self)

            self.punched = true
            self.punch_direction = puncher:get_look_dir()
    	end
    end
}

minetest.register_entity("cars:car", car_entity)

minetest.register_tool("cars:car", {
	description = "car (Place on road only. Sneak+Click to pick up)",
	--inventory_image = minetest.inventorycube("cars_car_top.png", "cars_car_side.png", "cars_car_side.png"),
    inventory_image = "streets_melcar_inv.png",
	--wield_image = "cars_car_side.png",
    wield_image = "streets_melcar_inv.png",

	on_place = function(itemstack, placer, pointed_thing)
		local under = pointed_thing.under
		local node = minetest.get_node(under)
		local udef = minetest.registered_nodes[node.name]
        local wear = itemstack:get_wear()
		if udef and udef.on_rightclick and
				not (placer and placer:get_player_control().sneak) then
			return udef.on_rightclick(under, node, placer, itemstack,
				pointed_thing) or itemstack
		end

		if not pointed_thing.type == "node" then
			return
		end
        local car = nil
        if minetest.get_node(pointed_thing.under).name == "asphalt:asphalt" then
            cars.set_fuel(car_entity, cars.fuel_from_wear(wear))    --no idea why this works...
            cars.set_old_direction(car_entity, yaw_vector(placer:get_look_horizontal()))
			car = minetest.add_entity({x=pointed_thing.under.x, y=pointed_thing.under.y+1, z=pointed_thing.under.z}, "cars:car")
        elseif minetest.get_item_group(minetest.get_node(pointed_thing.under).name, "cracky") > 0 then
            cars.set_fuel(car_entity, cars.fuel_from_wear(wear))    --no idea why this works...
            cars.set_old_direction(car_entity, yaw_vector(placer:get_look_horizontal()))
			car = minetest.add_entity({x=pointed_thing.under.x, y=pointed_thing.under.y+1, z=pointed_thing.under.z}, "cars:car")
        elseif minetest.get_node(pointed_thing.above).name == "asphalt:asphalt" then
            cars.set_fuel(car_entity, cars.fuel_from_wear(wear))
            cars.set_old_direction(car_entity, yaw_vector(placer:get_look_horizontal()))
			car = minetest.add_entity({x=pointed_thing.above.x, y=pointed_thing.above.y+1, z=pointed_thing.above.z}, "cars:car")
		else
			return
		end

		minetest.sound_play({name = "default_place_node_metal", gain = 0.5},
			{pos = pointed_thing.above})

		if not (creative and creative.is_enabled_for
				and creative.is_enabled_for(placer:get_player_name())) then
			itemstack:take_item()
		end
		return itemstack
	end,
})

cars.fuel_from_wear = function(wear)
	local fuel
	if wear == 0 then
		fuel = 1000
	else
		fuel = (65535-(wear-1))*1000/65535
	end
	return fuel
end

cars.wear_from_fuel = function(fuel)
	local wear = (1000-(fuel))*65535/1000+1
	if wear > 65535 then wear = 65535 end
	return wear
end

cars.get_fuel = function(self)
	return self.fuel
end

cars.set_fuel = function(self, fuel, object)
	self.fuel = fuel
end

cars.set_old_direction = function(self, v, object)
	self.old_direction = v
end

cars.car_to_item = function(self)
	local wear = cars.wear_from_fuel(cars.get_fuel(self))
	return {name="cars:car",wear=wear}
end

minetest.register_craft({
	output = "cars:car",
	recipe = {
        {"default:glass", "default:glass", "default:glass"},
		{"default:steelblock", "default:steelblock", "default:steelblock"},
		{"asphalt:bucket_oil", "", "asphalt:bucket_oil"},
	},
})
minetest.register_craft({
	type = "shapeless",
	output = "default:steelblock 3",
	recipe = {"cars:car"},
})
