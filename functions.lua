-- function cars:get_sign(z)
-- 	if z == 0 then
-- 		return 0
-- 	else
-- 		return z / math.abs(z)
-- 	end
-- end

-- function cars:velocity_to_dir(v)
-- 	if math.abs(v.x) > math.abs(v.z) then
-- 		return {x=cars:get_sign(v.x), y=cars:get_sign(v.y), z=0}
-- 	else
-- 		return {x=0, y=cars:get_sign(v.y), z=cars:get_sign(v.z)}
-- 	end
-- end

--vector to yaw
function vector_yaw(v)
    local yaw = math.pi
    if v.z < 0 then
        yaw = math.pi - math.atan(v.x/v.z)
    elseif v.z > 0 then
        yaw = -math.atan(v.x/v.z)
    elseif v.x > 0 then
        yaw = -math.pi/2
    elseif v.x < 0 then
        yaw = math.pi/2
    end
    return yaw
end

--yaw to vector
function yaw_vector(yaw)
    local v = {x=0, y=0, z=0}

    yaw = yaw + math.pi/2
    v.x = math.cos(yaw)
    v.z = math.sin(yaw)
    return v
end

function cars:manage_attachment(player, obj, seat)
	if not player then
		return
	end
	local status = obj ~= nil
	local player_name = player:get_player_name()
	if default.player_attached[player_name] == status then
		return
	end
	default.player_attached[player_name] = status

	if status then
        if seat == 2 then
            player:set_attach(obj, "", {x=0, y=8, z=-8}, {x=0, y=0, z=0})
            player:set_eye_offset({x=0, y=-2, z=-8},{x=0, y=-2, z=-8})
        else
    		player:set_attach(obj, "", {x=0, y=6, z=0}, {x=0, y=0, z=0})
            player:set_eye_offset({x=0, y=-4, z=0},{x=0, y=-4, z=0})
        end
	else
		player:set_detach()
		player:set_eye_offset({x=0, y=0, z=0},{x=0, y=0, z=0})
	end
end
