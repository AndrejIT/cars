
cars = {}
cars.modpath = minetest.get_modpath("cars")
cars.railparams = {}

-- Maximal speed of the car in m/s (min = -1)
cars.speed_max = 10
-- Pressing shift
cars.speed_max_turbo = 20
-- Set to -1 to disable punching the car from inside (min = -1)
cars.punch_speed_max = 5


dofile(cars.modpath.."/functions.lua")

-- Support for non-default games
if not default.player_attached then
	default.player_attached = {}
end

dofile(cars.modpath.."/car_entity.lua")
