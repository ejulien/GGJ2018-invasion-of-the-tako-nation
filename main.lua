hg = require("harfang")
plus = hg.GetPlus()

width = 720
height = 1280
playfield_padding = 50

player_damping = 0.999
player_radius = 50
player_to_player_collision_damping = 0.5
player_to_wall_collision_damping = 0.5

player_decoy_coef = -0.075
shoot_to_player_transfer_coef = 0.125

shoot_radius = 20
shoot_speed = 40
shoot_hold_duration = hg.time_from_sec(4)

ai_min_delay = hg.time_from_sec_f(0.5)
ai_max_delay = hg.time_from_sec_f(2.5)
ai_precision_delta = math.rad(5)
ai_aiming_speed = 0.1

human_health = 0
alien_health = 0

piout = nil
beep = nil
explosion = nil
bidon = nil
tako = nil

function LoadSoundFXs()
    explosion = plus:GetMixer():LoadSound("@data:explosion.ogg")
    beep = plus:GetMixer():LoadSound("@data:beep.ogg")
    piout = plus:GetMixer():LoadSound("@data:piout.ogg")
    bidon = plus:GetMixer():LoadSound("@data:bidon.ogg")
    tako = plus:GetMixer():LoadSound("@data:tako.ogg")
    if tako ~= nil then
        return true
    else
        return false
    end
end

function create_player()
    p = {}
    
    p.pos = hg.Vector2(0, 0)
    p.spd = hg.Vector2(0, 0)
    p.angle = 0
    
    p.msg = ""
    msg_delay = 0

    p.ai = true
    p.ai_angle = 0
    p.ai_shot_delay = 0

    p.gamepad = nil

    return p
end    

players = {create_player(), create_player(), create_player(), create_player()}

gamepads = {0, 0, 0, 0}

function GetNextPlayer()
    for i = 1, #players do
        if players[i].ai then
            return i
        end
    end
end

function AnyButtonPressed()
    for i = 1, #gamepads do
        if InputDeviceWasButtonPressed(gamepads[i]) then
            return i
        end
    end

    return -1
end

players_color = {hg.Color(238 / 255, 94 / 255, 255 / 255), hg.Color(251 / 255, 220 / 255, 46 / 255), hg.Color(32 / 255, 255 / 255, 63 / 255), hg.Color(36 / 255, 227 / 255, 255 / 255)}

function AngleToDirection(angle)
	angle = -angle + math.rad(90)
	return hg.Vector2(math.sin(angle), math.cos(angle))
end

function DirectionToAngle(dir)
    return math.atan(dir.y, dir.x)
end

function GetAIDelay()
    return math.random() * (ai_max_delay - ai_min_delay) + ai_min_delay
end

function DrawText2DCentered(x, y, text, size, color, font_path)
    local rect = plus:GetTextRect(text, size, font_path)
    plus:Text2D(x - rect:GetWidth() / 2, y + rect:GetHeight() / 2, text, size, color, font_path)
end

function SetPlayerMessage(player, msg) 
	player.msg = msg
	player.msg_delay = hg.time_from_sec(2)
end

function DrawPlayerMessage(player)
	if player.msg_delay > 0 then
        local x = player.pos.x
        local y = player.pos.y + 38
		local alpha = ClampAuto((player.msg_delay) / hg.time_from_sec_f(0.2))

		DrawText2DCentered(x, y, player.msg, 18, hg.Color(0, 0, 0, 0.5 * alpha), "@data:komikax.ttf")
		DrawText2DCentered(x - 2, y + 2, player.msg, 18, hg.Color(1, 1, 1, 1 * alpha), "@data:komikax.ttf")
		player.msg_delay = player.msg_delay - hg.GetLastFrameDuration()
    end
end

function DrawPlayer(idx, col)
	local player = players[idx]

	local shots = GetPlayerShoots(idx)

	if #shots > 0 then
		plus:Sprite2D(player.pos.x, player.pos.y, 160, "@data:drone_buffer.png", players_color[idx])
		plus:Text2D(player.pos.x - 6, player.pos.y - 12, #shots, 32, players_color[idx], "@data:impact.ttf")
	else
		plus:Sprite2D(player.pos.x, player.pos.y, 160, "@data:drone.png", players_color[idx])
    end

	if #shots > 0 then
		local shot = shoots[shots[1]]

		local tgt_col
		if shot.player_seq_idx == 4 then
			tgt_col = hg.Color.Red
		else
			local tgt_idx = shot.player_seq[shot.player_seq_idx + 1]
			tgt_col = players_color[tgt_idx]
        end

		local dir = AngleToDirection(player.angle)
		plus:RotatedSprite2D(player.pos.x, player.pos.y, player.angle - math.rad(90), 160, "@data:drone_arrow.png", tgt_col)
    end
end

function PlayerFireShot(player_idx, idx)
	local player = players[player_idx]
	local shoot = shoots[idx]

    local dir = AngleToDirection(player.angle)
	shoot.pos = player.pos + dir * player_radius -- prevent self collision
	shoot.spd = dir * shoot_speed
	shoot.hold_until = 0
	player.spd = player.spd + (shoot.spd * player_decoy_coef)
	assert(shoot.player_seq_idx < 5)
	shoot.player_seq_idx = shoot.player_seq_idx + 1

	plus:GetMixer():Start(piout)
end

function GetShootNextTargetPos(shot)
	if (shot.player_seq_idx + 1) == 5 then -- sequence end: shot alien!
        return hg.Vector2(width / 2, 0)
    end

	local tgt_idx = shot.player_seq[shot.player_seq_idx + 1]
	return players[tgt_idx].pos
end

function UpdatePlayer(idx)
	local player = players[idx]

	player.pos = player.pos + player.spd
	player.spd = player.spd * player_damping

	if player.ai then
		local shots = GetPlayerShoots(idx)

		if #shots > 0 then
			local shot = shoots[shots[1]]
			local tgt_pos = GetShootNextTargetPos(shot)
			local dir = (tgt_pos - player.pos):Normalized()
			player.ai_angle = DirectionToAngle(dir) + FRRand(-ai_precision_delta, ai_precision_delta)
			player.angle = player.angle + ((player.ai_angle - player.angle) * ai_aiming_speed)

			player.ai_shot_delay = player.ai_shot_delay - hg.GetLastFrameDuration()

            if player.ai_shot_delay < 0 then
				PlayerFireShot(idx, shots[1])
				player.ai_shot_delay = GetAIDelay()
            end
        end
    end
end

function PlayerCollidePlayfield(player)
	local playfield_padding_augmented = playfield_padding + player_radius

	local sfx = false

	if player.pos.x > (width - playfield_padding_augmented) then
		if player.spd.x > 0 then
            player.spd.x = player.spd.x * -player_to_wall_collision_damping
        end
		sfx = true
    end
	if player.pos.x < playfield_padding_augmented then
		if player.spd.x < 0 then
            player.spd.x = player.spd.x * -player_to_wall_collision_damping
        end
		sfx = true
    end
	if player.pos.y > (height - playfield_padding_augmented * 3.5) then
		if player.spd.y > 0 then
            player.spd.y = player.spd.y * -player_to_wall_collision_damping
        end
		sfx = true
    end
	if player.pos.y < playfield_padding_augmented * 3.5 then
		if player.spd.y < 0 then
            player.spd.y = player.spd.y * -player_to_wall_collision_damping
        end
		sfx = true
    end

    if (sfx) then
        plus:GetMixer():Start(bidon)
    end
end

function PlayerCollidePlayer(a, b)
	local d = b.pos - a.pos
	local l = d:Len()

	if l < player_radius * 2 then
		local k = (player_radius * 2 - l) * player_to_player_collision_damping
		local v = d * (k / l)

		b.spd = b.spd + v
		a.spd = a.spd - v

		plus:GetMixer():Start(bidon)
    end
end

function UpdatePlayersCollision()
	for i = 1, #players, 1 do
		for j = 1, #players, 1 do
			if i ~= j then
                PlayerCollidePlayer(players[i], players[j])
            end
        end
    end

	for k, player in pairs(players) do
        PlayerCollidePlayfield(player)
    end
end


function UpdatePlayerInputs(idx, device)
	local player = players[idx]

	if not player.ai then
		player.angle = InputDeviceGetAngle(device)

		if InputDeviceWasButtonPressed(device) then
			local shots = GetPlayerShoots(idx)
			if #shots > 0 then
                PlayerFireShot(idx, shots[1])
            end
        end
    end
end

function ShootAtTarget(shoot, tgt)
	shoot.spd = (tgt - shoot.pos):Normalized() * shoot_speed
    shoot.hold_until = 0
    return shoot
end

function InitShoot()
    local shoot = {}
    shoot.player_seq = {}
    for i = 1, 4, 1 do
        shoot.player_seq[i] = i
    end

    for i = 1, 4, 1 do
        local a = 1 + math.random() * 3.999
        local a_int = math.floor(a) 
        local b = 1 + math.random() * 3.999
        local b_int = math.floor(b) 
		local tmp = shoot.player_seq[a_int]
		shoot.player_seq[a_int] = shoot.player_seq[b_int]
		shoot.player_seq[b_int] = tmp
    end

	shoot.player_seq_idx = 1
	shoot.pos = hg.Vector2(width / 2, 0)
	shoot.hold_until = 0 

    shoot = ShootAtTarget(shoot, players[shoot.player_seq[shoot.player_seq_idx]].pos)
    return shoot
end

function GetPlayerShoots(idx)
	local shoot_idxs = {}
    for i, shoot in ipairs(shoots) do
		if shoot.hold_until ~= 0 and (shoot.player_seq[shoot.player_seq_idx] == idx) then
            table.insert(shoot_idxs, i)
        end
    end
	return shoot_idxs
end

earth_msg = ""
earth_msg_duration = 0

function SetEarthMessage(msg)
	earth_msg = msg
	earth_msg_duration = hg.time_from_sec(2)
end

function GetEarthPos() 
    return hg.Vector2(width / 2, height - 120)
end

function DrawEarthMessage()
	if earth_msg_duration > 0 then
		local pos = GetEarthPos()
		local alpha = ClampAuto((earth_msg_duration) / hg.time_from_sec_f(0.2))

		DrawText2DCentered(pos.x, pos.y, earth_msg, 64, hg.Color(0, 0, 0, 0.75 * alpha), "@data:komikax.ttf")
		DrawText2DCentered(pos.x - 8, pos.y + 8, earth_msg, 64, hg.Color(1, 1, 1, 1 * alpha), "@data:komikax.ttf")
		earth_msg_duration = earth_msg_duration - hg.GetLastFrameDuration()
    end
end

alien_msg = ""
alien_msg_duration = 0

function SetAlienMessage(msg)
	alien_msg = msg
	alien_msg_duration = hg.time_from_sec(2)
end

function GetAlienPos()
    local x = width / 2
    local y = 60

	local offset = FRRand(-4, 4)
	x = x + offset
	y = y + offset

	return hg.Vector2(x, y)
end

function DrawAlienMessage()
	if alien_msg_duration > 0 then
		local pos = GetAlienPos()
		local alpha = ClampAuto((alien_msg_duration) / hg.time_from_sec_f(0.2))

		DrawText2DCentered(pos.x, pos.y, alien_msg, 64, hg.Color(0, 0, 0, 0.75 * alpha), "@data:komikax.ttf")
		DrawText2DCentered(pos.x - 8, pos.y + 8, alien_msg, 64, hg.Color(1, 0, 0, 1 * alpha), "@data:komikax.ttf")
		alien_msg_duration = alien_msg_duration - hg.GetLastFrameDuration()
    end
end

function SpawnBloodSplatFX(pos, path)
	for i = 0, 3, 1 do
		SpawnFX(pos.x + FRRand(-width * 0.5, width * 0.5), pos.y + FRRand(-20, 20), path, FRRand(200, 600), FRRand(0, 2), hg.time_from_sec(1), hg.time_from_sec_f(FRRand(0, 1)), hg.Color(1, 1, 1), 0)
    end
end

function UpdateShoot(idx)
	local shoot = shoots[idx]

    local out_of_bound = false

	if shoot.hold_until == 0 then
        shoot.pos = shoot.pos + shoot.spd

		-- detect drone collision
		for i = 1, 4, 1 do
			local player = players[i]
			if hg.Vector2.Dist(shoot.pos, player.pos) < (shoot_radius + player_radius) then
				local correct_transfer = true

				if shoot.player_seq_idx == 5 then -- alien expected
					correct_transfer = false
                else
                    if i == shoot.player_seq[shoot.player_seq_idx] then
                        correct_transfer = true
                    else
                        correct_transfer = false
                    end
                end

				if correct_transfer then
					shoot.hold_until = shoot_hold_duration
					player.spd = player.spd + (shoot.spd * shoot_to_player_transfer_coef)

					SpawnFX(player.pos.x, player.pos.y, "@data:fx_donut.png", 200, 0, hg.time_from_sec_f(0.2), 0, hg.Color(1, 1, 1, 0.75), 8)
                end
            end
        end

		-- detect out of playfield
		local could_hit_alien = false

		if (shoot.pos.x < -shoot_radius) then
			out_of_bound = true
		elseif shoot.pos.x > width + shoot_radius then
			out_of_bound = true
        elseif shoot.pos.y < -shoot_radius then
			could_hit_alien = true
			out_of_bound = true
		elseif shoot.pos.y > height + shoot_radius then
			out_of_bound = true
        end

		if out_of_bound == true then
			if shoot.player_seq_idx == 1 then -- initial alien shot
				SetAlienMessage("Human escape!")
				plus:GetMixer():Start(piout)
			elseif shoot.player_seq_idx == 5 then -- last human shot
				if could_hit_alien then
					SetPlayerMessage(players[shoot.player_seq[4]], "Humanity hero!")
					SetAlienMessage("Sufffering!")
					SpawnBloodSplatFX(GetAlienPos(), "@data:alien_blood.png")
					ShakeBG(10)
					alien_health = alien_health - 5
					plus:GetMixer():Start(tako)
				else 
					SetPlayerMessage(players[shoot.player_seq[4]], "You drunkard!")
					SetAlienMessage("Alien missed!")
					SetEarthMessage("Genocide!")
					SpawnBloodSplatFX(GetEarthPos(), "@data:human_blood.png")
					ShakeBG(10)
					human_health = human_health - 10
					plus:GetMixer():Start(explosion)
                end
			else 
				SetPlayerMessage(players[shoot.player_seq[shoot.player_seq_idx - 1]], "Chain breaker!")
				SpawnBloodSplatFX(GetEarthPos(), "@data:human_blood.png")
				SetEarthMessage("Cataclysm!")
				ShakeBG(4)
				human_health = human_health - 5
				plus:GetMixer():Start(explosion)
            end
        end
    end

    return out_of_bound
end

function UpdateShoots()
    local shoots_alive = {}
	for i = 1, #shoots do
        if not UpdateShoot(i) then
            table.insert(shoots_alive, shoots[i])
        end
    end
    shoots = shoots_alive
end

function DrawShoot(shoot)
	if shoot.hold_until == 0 then
		plus:RotatedSprite2D(shoot.pos.x, shoot.pos.y, DirectionToAngle(shoot.spd), 150, "@data:drone_shoot.png", hg.Color.White, 93 / 150, 0.5)
    end
end

function DrawShoots() 
	for k, shoot in pairs(shoots) do
        DrawShoot(shoot)
    end
end 

function SpawnShoot()
    local shoot = InitShoot()
    SetAlienMessage("Attack!")
    table.insert(shoots, shoot)
end

next_shoot_delay = 0

function HeuristicSpawnShoot()
	next_shoot_delay = next_shoot_delay - hg.GetLastFrameDuration()
	if next_shoot_delay < 0 then
		next_shoot_delay = hg.time_from_sec_f(FRRand(1, 3.5))
		SpawnShoot()
    end
end

function DrawHealthBar(x, y, health)
	local idx = Clamp(math.floor((health + 9) / 10), 0, 10) * 10
	local path = "@data:life_bar_"..idx..".png"
	plus:Image2D(x, y, 1, path)
end

function DrawUI()
	plus:Sprite2D(80, height - 200, 120, "@data:alien_avatar.png")
	plus:Sprite2D(width - 80, height - 200, 120, "@data:human_avatar.png")

	DrawHealthBar(80 + 40, height - 200, alien_health)
	DrawHealthBar(width - 80 - 40 - 230, height - 200, human_health)

	for k, player in pairs(players) do
		DrawPlayerMessage(player)
    end
	DrawEarthMessage() 
	DrawAlienMessage()
end

bg_shake_strength = 0

function ShakeBG(strength)
    bg_shake_strength = strength
end

function DrawBG()
    local shake_offx = FRRand(-1, 1)
    local shake_offy = FRRand(-1, 1)
	plus:Image2D(shake_offx * bg_shake_strength, shake_offy * bg_shake_strength, 1, "@data:space_bg.jpg")
	bg_shake_strength = bg_shake_strength * 0.95

	local a = hg.time_to_sec_f(plus:GetClock())
	local alien_x = math.cos(a * 0.75) * 25

    plus:Image2D(alien_x, -(100 - alien_health), 1, "@data:tentacles.png")
end

fxs = {}

function DrawFXs()
	local k_fade = hg.time_from_sec_f(0.25)

    for k, fx in pairs(fxs) do 

        if fx.delay > 0 then
			fx.delay = fx.delay - hg.GetLastFrameDuration()
		else 
			local alpha = ClampAuto(fx.duration / k_fade)
			local col = fx.color
			col.a = col.a * alpha
			plus:RotatedSprite2D(fx.pos.x, fx.pos.y, fx.rotation, fx.size, fx.img, col)
			fx.size = fx.size + fx.size_spd
			fx.duration = fx.duration - hg.GetLastFrameDuration()
        end
    end

    alive_fxs = {}

    for k, fx in pairs(fxs) do 
        if fx.duration >= 0 then
            table.insert(alive_fxs, fx)
        end
    end

    fxs = alive_fxs
end

function SpawnFX(x, y, img, size, rotation, duration, delay, color, size_spd)
    fx = {}
    fx.img = img
	fx.pos = hg.Vector2(x, y)
	fx.size = size
	fx.rotation = rotation
	fx.delay = delay
	fx.duration = duration
	fx.color = color
    fx.size_spd = size_spd
    table.insert( fxs, #fxs + 1, fx)
end

fade_color = hg.Color(1, 1, 1, 0)
fade_to = hg.Color(1, 1, 1, 0)
fade_duration = hg.time_from_sec(0)
fade_t = hg.time_from_sec(0)

function FullscreenQuad(color)
	plus:Quad2D(0, 0, 0, height, width, height, width, 0, color, color, color, color)
end

function IsFading()
    return fade_duration > 0
end

function SetFade(color)
    fade_color = color
end

function FadeTo(color, duration)
    fade_to = color
    fade_duration = duration 
    fade_t = fade_duration
end

function FadeToAuto(color)
    fade_to = color
    fade_duration = hg.time_from_sec_f(0.25)
    fade_t = fade_duration
end

function DrawFade()
    local col = hg.Color()

	if fade_duration > 0 then
		local k = hg.time_to_sec_f(fade_duration) / hg.time_to_sec_f(fade_t)
		col = fade_color * k + fade_to * (1 - k)
		fade_duration = fade_duration - hg.GetLastFrameDuration()
	else
        fade_color = fade_to
        col = fade_color
    end
    if col.a ~= 0 then
        FullscreenQuad(col)
    end
end

game_over_img = ""

function DrawGameOver()
	plus:Image2D(0, 0, 1, "@data:default_screen.jpg")
	plus:Image2D(0, 550, 1, game_over_img)
end

function GameOverFade()
	DrawGameOver()

	if IsFading() then
		return false
    end
	next_game_state = Title
	return true
end

function GameOver() 
	DrawGameOver()

    if not IsFading() and AnyButtonPressed() ~= -1 then
		SetFade(hg.Color(0, 0, 0, 0))
		FadeTo(hg.Color.Black, hg.time_from_sec(1))
		next_game_state = GameOverFade
        return true
    end

	return false
end

function GameLoopCommon()
    
	DrawBG()

	UpdatePlayersCollision()

	for i = 1, #players do
		UpdatePlayerInputs(i, gamepads[players[i].gamepad]) -- CHANGE gamepads[i]
		UpdatePlayer(i)
		DrawPlayer(i, players_color[i])
    end

	HeuristicSpawnShoot()
	UpdateShoots()
	DrawShoots()

	DrawFXs()
	DrawUI()
end

attract_mode = false
attract_mode_duration = 0

function FRRand(min, max)
    return min + math.random() * (max - min)
end

function FRand(angle)
    return math.random() * angle
end

function GameInit()
    fxs = {}
	shoots = {}

	earth_msg_duration = 0
	alien_msg_duration = 0

    for k, player in pairs(players) do
        player.pos = hg.Vector2(FRRand(100, 620), FRRand(400, 800))
		player.spd = hg.Vector2(FRRand(-0.1, 0.1), FRRand(-0.1, 0.1))
		player.angle = FRand(math.rad(360))
		player.ai_shot_delay = math.floor(GetAIDelay())
		player.msg_delay = 0
	end

	human_health = 100
	alien_health = 100

	next_game_state = GameLoop
	next_shoot_delay = hg.time_from_sec(3)

	SetAlienMessage("GraaawwwR!")

	SetFade(hg.Color.Black)
	FadeToAuto(hg.Color(0, 0, 0, 0))

	attract_mode = false
    return true
end

function AttractMode()
    for k, player in pairs(players) do
        player.ai = true
    end

    GameInit()

    attract_mode = true
    attract_mode_duration = hg.time_from_sec(20)

    SetFade(hg.Color.White)
    FadeToAuto(hg.Color(1, 1, 1, 0))
    return true
end

function GameDebugKeys()
	if plus:KeyDown(hg.KeyF1) then
        human_health = 0
    end
	if plus:KeyDown(hg.KeyF2) then
        alien_health = 0
    end
end

function GameLoop()
    if attract_mode then
		attract_mode_duration = attract_mode_duration - hg.GetLastFrameDuration()
		if attract_mode_duration < 0 or human_health < 10 or alien_health < 10 or (AnyButtonPressed() ~= -1) then
			next_game_state = Title
			return true
        end
    end

	GameLoopCommon()
	GameDebugKeys()

	if alien_health <= 0 then
		SetFade(hg.Color.Blue)
		FadeTo(hg.Color(1, 0, 0, 0), hg.time_from_sec(3))
		game_over_img = "@data:victory_text.png"
        next_game_state = GameOver
		return true
	elseif human_health <= 0 then
		SetFade(hg.Color.Red)
		FadeTo(hg.Color(1, 0, 0, 0), hg.time_from_sec(3))
		game_over_img = "@data:game_over_text.png"
        next_game_state = GameOver
		return true
    end

	if attract_mode then
		if (attract_mode_duration % hg.time_from_sec_f(1)) > hg.time_from_sec_f(0.5) then
			plus:Image2D(0, 80, 1, "@data:press_any_button_text.png")
        end
    end

	return false
end

how_to_play_time = 0
how_to_play_can_start_game = false
how_to_play_branch_to = nil

function HowToPlayWaitFade()
    plus:Image2D(0, 0, 1, "@data:default_screen.jpg")
	plus:Image2D(0, 0, 1, "@data:how_to_play_02.png")

	 if not IsFading() then
         next_game_state = how_to_play_branch_to
         return true
     end

	return false
end

function HowToPlayScreen()
   plus:Image2D(0, 0, 1, "@data:default_screen.jpg")

	if how_to_play_time > hg.time_from_sec(8) then
		plus:Image2D(0, 0, 1, "@data:how_to_play_02.png")
        if AnyButtonPressed() ~= -1 then
            how_to_play_time = hg.time_from_sec(16)
        end
	else
		plus:Image2D(0, 0, 1, "@data:how_to_play_01.png")
        if AnyButtonPressed() ~= -1 then
            how_to_play_time = hg.time_from_sec(8)
        end
    end

	if how_to_play_time > hg.time_from_sec(16) then
		SetFade(hg.Color(0, 0, 0, 0))
		FadeTo(hg.Color.Black, hg.time_from_sec_f(0.5))
		next_game_state = HowToPlayWaitFade
		return true
    end

	how_to_play_time = how_to_play_time + hg.GetLastFrameDuration()
	return false
end

function HowToPlay()
    how_to_play_time = 0
	SetFade(hg.Color.White)
	FadeToAuto(hg.Color(1, 1, 1, 0))
	next_game_state = HowToPlayScreen
	return true
end

join_delay = 0

function DrawPlayerJoinScreen()
    plus:Image2D(0, 0, 1, "@data:default_screen.jpg")
    plus:Image2D(0, 0, 1, "@data:join_overlay.png")

    FullscreenQuad(hg.Color(0, 0, 0, 0.75))

    DrawText2DCentered(width / 4, height / 4 - 40, players[1].ai and "CPU" or "P1", 128, players_color[1], "@data:impact.ttf")
    DrawText2DCentered(width / 4, height / 4 * 3 - 40, players[2].ai and "CPU" or "P2", 128, players_color[2], "@data:impact.ttf")
    DrawText2DCentered(width / 4 * 3, height / 4 - 40, players[3].ai and "CPU" or "P3", 128, players_color[3], "@data:impact.ttf")
    DrawText2DCentered(width / 4 * 3, height / 4 * 3 - 40, players[4].ai and "CPU" or "P4", 128, players_color[4], "@data:impact.ttf")

    DrawText2DCentered(width / 4, height / 4 - 120, players[1].ai and "Join now!" or "Get ready!", 48, players_color[1], "@data:impact.ttf")
    DrawText2DCentered(width / 4, height / 4 * 3 - 120, players[2].ai and "Join now!" or "Get ready!", 48, players_color[2], "@data:impact.ttf")
    DrawText2DCentered(width / 4 * 3, height / 4 - 120, players[3].ai and "Join now!" or "Get ready!", 48, players_color[3], "@data:impact.ttf")
    DrawText2DCentered(width / 4 * 3, height / 4 * 3 - 120, players[4].ai and "Join now!" or "Get ready!", 48, players_color[4], "@data:impact.ttf")

    DrawText2DCentered(width / 2, height / 2 - 160, hg.time_to_sec(join_delay), 190, hg.Color.White, "@data:komikax.ttf")
end

function WaitJoinFadeOut()
    DrawPlayerJoinScreen()

    if not IsFading() then
        next_game_state = HowToPlay
        return true
    end
    return false
end

function GetPlayerUsingGamepad(idx)
    for k, player in pairs(players) do
        if player.gamepad == idx then
            return player
        end
    end
    return nil
end

function RegisterNewHumanPlayer(pad_idx)
    next_player_idx = GetNextPlayer()

    if next_player_idx ~= nil then
        plus:GetMixer():Start(beep)

        player = players[next_player_idx]
        player.ai = false
        player.gamepad = pad_idx
    end
end

function PlayerJoinScreen()
    DrawPlayerJoinScreen()

    local pad_idx = AnyButtonPressed()
    if pad_idx ~= -1 then
        player = GetPlayerUsingGamepad(pad_idx)

        if player == nil then
           RegisterNewHumanPlayer(pad_idx)
        else
            join_delay = join_delay - hg.time_from_sec(1)
        end
    end

    local join_done = true
    for k, player in pairs(players) do
        if player.ai then
            join_done = false
        end
    end

    join_delay = join_delay - hg.GetLastFrameDuration()
    if join_delay < 0 then
        join_delay = 0
        join_done = true
    end

    if join_done then
        SetFade(hg.Color(0, 0, 0, 0))
        FadeTo(hg.Color.Black, hg.time_from_sec(1))
        next_game_state = WaitJoinFadeOut
        return true
    end

    return false
end

function InitJoinScreen() 
    how_to_play_branch_to = GameInit
    how_to_play_can_start_game = false
    join_delay = hg.time_from_sec(10)
end

function DetectGameStart()
    local pad_idx = AnyButtonPressed()

    if pad_idx ~= -1 then

        for k, player in pairs(players) do
            player.ai = true
        end

        RegisterNewHumanPlayer(pad_idx)

        InitJoinScreen()
        next_game_state = PlayerJoinScreen

        SetFade(hg.Color.White)
        FadeToAuto(hg.Color(1, 1, 1, 0)) 
        return true
    end
    return false
end

intro_seq = 0
intro_seq_delay = 0
intro_t = 0

function Clamp(v, mn, mx)
    return math.min(math.max(v, mn), mx)
end

function ClampAuto(v)
    return math.min(math.max(v, 0), 1)
end

function Lerp(a, b, t)
    return (b - a) * t + a
end

function DrawTitle()
    plus:Image2D(0, 0, 1, "@data:intro_bg.jpg")

    local t_earth = Clamp(hg.time_to_sec_f(intro_t) / 18, 0, 1)
    local earth_pos = Lerp(hg.Vector2(0, -400), hg.Vector2(0, 0), t_earth)

    plus:Image2D(earth_pos.x, earth_pos.y, 1, "@data:intro_earth.png")
    if intro_seq >= 4 then
        plus:Image2D(width -455, height -520, 1, "@data:intro_alien.png")
    end

    if intro_seq > 0 then
        plus:Image2D(0, height / 2 -140, 1, "@data:intro_text0"..Clamp(intro_seq, 1, 4)..".png")
    end

    if intro_t % hg.time_from_sec_f(1) > hg.time_from_sec_f(0.5) then

        plus:Image2D(0, 80, 1, "@data:press_any_button_text.png")
    end

    intro_t = intro_t + hg.GetLastFrameDuration()
end

title_loop_attract = true

function TitleWaitFadeOut()
    if DetectGameStart() then
        return true
    end

    DrawTitle()

    if not IsFading() then

        if title_loop_attract == true then 
            next_game_state = AttractMode
        else
            next_game_state = HowToPlay
        end
        title_loop_attract = not title_loop_attract
        how_to_play_can_start_game = true
        return true
    end
    return false
end

function IntroAndTitleScreen()
    
    if DetectGameStart() then
        return true
    end

    DrawTitle()

    intro_seq_delay = intro_seq_delay - hg.GetLastFrameDuration()

    if intro_seq_delay < 0 then
        intro_seq = intro_seq + 1

        if intro_seq == 5 then
            SetFade(hg.Color(0, 0, 0, 0))
            FadeTo(hg.Color.Black, hg.time_from_sec(2))
            next_game_state = TitleWaitFadeOut
            return true
        elseif intro_seq == 4 then
            intro_seq_delay = hg.time_from_sec(6)
            SetFade(hg.Color.White)
            FadeTo(hg.Color(1, 1, 1, 0), hg.time_from_sec(1))
        else
            intro_seq_delay = hg.time_from_sec(3)
        end
    end

    return false
end

function Title()
    SetFade(hg.Color(0, 0, 0, 1))
    FadeTo(hg.Color(0, 0, 0, 0), hg.time_from_sec(6))

    intro_t = 0
    intro_seq = 0
    intro_seq_delay = hg.time_from_sec(6)

    next_game_state = IntroAndTitleScreen
    how_to_play_branch_to = Title
    how_to_play_can_start_game = false
    return true
end

keyboard_configs = { -- fire, left, right
    {{hg.KeyZ, hg.KeyW}, {hg.KeyQ, hg.KeyA}, hg.KeyD},
    {hg.KeyO, hg.KeyK, hg.KeyM},
    {hg.KeyUp, hg.KeyLeft, hg.KeyRight},
    {hg.KeyNumpad8, hg.KeyNumpad4, hg.KeyNumpad6}
}

function NewGamepadDevice(device)
    return {type = 'gamepad', device = device, angle = 0}
end

function NewKeyboardDevice(device, cfg)
    return {type = 'keyboard', device = device, keys_cfg = cfg, angle = 0}
end

function KeyboardTestInput(device, kbd_cf_idx, test)
    local input = keyboard_configs[device.keys_cfg][kbd_cf_idx]
    if type(input) == 'table' then
        for i = 1, #input do 
            if test(device, input[i]) then
                return true
            end
        end
    else
        if test(device, input) then
            return true
        end
    end
    return false
end

function KeyboardInputWasDown(device, kbd_cf_idx)
    local test = function(device, btn) return device.device:WasDown(btn) end
    return KeyboardTestInput(device, kbd_cf_idx, test)
end

function KeyboardInputWasPressed(device, kbd_cf_idx)
    local test = function(device, btn) return device.device:WasPressed(btn) end
    return KeyboardTestInput(device, kbd_cf_idx, test)
end

function InputDeviceWasButtonPressed(device)
    if device.type == 'gamepad' then
        if device.device:WasButtonPressed(hg.Button0) then
            return true
        end

    elseif device.type == 'keyboard' then
        if KeyboardInputWasPressed(device, 1) then
            return true
        end
    end
    return false
end

function InputDeviceGetAngle(device)
    if device.type == 'gamepad' then
        local v = hg.Vector2(device.device:GetValue(hg.InputAxisX), device.device:GetValue(hg.InputAxisY))
        local l = v:Len()

        if l > 0.25 then
            v = v / l
            device.angle = math.atan(v.y, v.x)
        end

    elseif device.type == 'keyboard' then

        if KeyboardInputWasDown(device, 2) then
            device.angle = device.angle - 0.2
        end

        if KeyboardInputWasDown(device, 3) then
            device.angle = device.angle + 0.2
        end
    end
    return device.angle
end

function SetupGamepads()
    gamepads[1] = NewGamepadDevice(hg.GetInputSystem():GetDevice("xinput.port0"))
    gamepads[2] = NewGamepadDevice(hg.GetInputSystem():GetDevice("xinput.port1"))
    gamepads[3] = NewGamepadDevice(hg.GetInputSystem():GetDevice("xinput.port2"))
    gamepads[4] = NewGamepadDevice(hg.GetInputSystem():GetDevice("xinput.port3"))
    gamepads[5] = NewKeyboardDevice(hg.GetInputSystem():GetDevice("keyboard"), 1)
    gamepads[6] = NewKeyboardDevice(hg.GetInputSystem():GetDevice("keyboard"), 2)
    gamepads[7] = NewKeyboardDevice(hg.GetInputSystem():GetDevice("keyboard"), 3)
    gamepads[8] = NewKeyboardDevice(hg.GetInputSystem():GetDevice("keyboard"), 4)

    if not gamepads[1] or not gamepads[2] or not gamepads[3] or not gamepads[4] then
        error("No Xinput support, falling back to keyboard")
        -- for i=1, #gamepads do
        --     gamepads[i] = hg.GetInputSystem():GetDevice("keyboard")
        -- end
    end
    return true
end

--------------------MAIN--------------------------
hg.SetLogLevel(hg.LogAll)
hg.LoadPlugins()

if not plus:RenderInit(720, 1280) or not plus:AudioInit() then
    return 1
end

plus:SetWindowTitle("Invasion of the Tako Nation - Harfang 3D")

if not SetupGamepads() then
    return 1
end

--DEBUG
plus:MountAs("C:/Users/movida-user/Desktop/Camille/Code/CPP/ggj2018/data", "@data:")

plus:SetBlend2D(hg.BlendAlpha)

if not LoadSoundFXs() then
    return 1
end

--plus:GetMixer():Stream("@data:zik.ogg", hg.RepeatState)

game_state = Title

while not plus:IsAppEnded() do
    plus:Clear(hg.Color.Black)
    
    if game_state() then
        game_state = next_game_state
    end

    DrawFade()

    plus:Flip()
    plus:EndFrame()
    plus:UpdateClock()
end

--exit(0)

--plus:RenderUninit()
--plus:AudioUninit()

--Uninit()

----------------------END MAIN----------------------------