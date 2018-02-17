#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <engine/engine.h>
#include <engine/init.h>
#include <engine/mixer.h>
#include <engine/plugin_system.h>
#include <engine/plus.h>
#include <engine/zip_file_driver.h>
#include <foundation/color_api.h>
#include <foundation/filesystem.h>
#include <foundation/log.h>
#include <foundation/math.h>
#include <foundation/path_tools.h>
#include <foundation/random.h>
#include <foundation/time.h>
#include <foundation/unit.h>
#include <foundation/vector2.h>
#include <functional>
#include <platform/input_device.h>
#include <platform/input_system.h>

using namespace hg;

//
constexpr int width = 720, height = 1280;
constexpr int playfield_padding = 50;

constexpr float player_damping = 0.999f;
constexpr float player_radius = 50.f;
constexpr float player_to_player_collision_damping = 0.5f;
constexpr float player_to_wall_collision_damping = 0.5f;

constexpr float player_decoy_coef = -0.075f;
constexpr float shoot_to_player_transfer_coef = 0.125f;

constexpr float shoot_radius = 20.f;
constexpr float shoot_speed = 40.f;
constexpr time_ns shoot_hold_duration = time_from_sec(4);

constexpr time_ns ai_min_delay = time_from_sec_f(0.5f);
constexpr time_ns ai_max_delay = time_from_sec_f(2.5f);
constexpr float ai_precision_delta = Deg(5.f);
constexpr float ai_aiming_speed = 0.1f;

//
int human_health, alien_health;

//   ddd
std::shared_ptr<hg::Sound> piout, beep, explosion, bidon, tako;

bool LoadSoundFXs() {
	explosion = g_plus.get().GetMixer()->LoadSound("@data:explosion.ogg");
	piout = g_plus.get().GetMixer()->LoadSound("@data:piout.ogg");
	beep = g_plus.get().GetMixer()->LoadSound("@data:beep.ogg");
	bidon = g_plus.get().GetMixer()->LoadSound("@data:bidon.ogg");
	tako = g_plus.get().GetMixer()->LoadSound("@data:tako.ogg");
	return bool(piout);
}

//
void DrawCircle(float x, float y, float radius, int nseg, const Color &col) {
	float step = Deg(360.f) / nseg, angle = 0.f;
	float sx = Sin(angle) * radius + x, sy = Cos(angle) * radius + y, ex, ey;
	for (int i = 0; i < nseg; ++i) {
		angle += step;
		ex = Sin(angle) * radius + x;
		ey = Cos(angle) * radius + y;
		g_plus.get().Line2D(sx, sy, ex, ey, col, col);
		sx = ex;
		sy = ey;
	}
}

void DrawDisc(float x, float y, float radius, int nseg, const Color &col) {
	float step = Deg(360.f) / nseg, angle = 0.f;
	float sx = Sin(angle) * radius + x, sy = Cos(angle) * radius + y, ex, ey;
	for (int i = 0; i < nseg; ++i) {
		angle += step;
		ex = Sin(angle) * radius + x;
		ey = Cos(angle) * radius + y;
		g_plus.get().Triangle2D(ex, ey, x, y, sx, sy, col, col, col);
		sx = ex;
		sy = ey;
	}
}

//
struct Shoot {
	std::array<int, 4> player_seq;
	int player_seq_idx;

	Vector2 pos;
	Vector2 spd;

	time_ns hold_until;
};

std::vector<Shoot> shoots;

void SpawnShoot();
std::vector<int> GetPlayerShoots(int idx);

void SpawnFX(float x, float y, const char *img, float size, float rotation = 0, time_ns duration = time_from_sec(2), time_ns delay = 0, Color color = Color(1, 1, 1, 1), float size_spd = 0.f);

void ShakeBG(float strength);

//
bool IsFading();
void FadeTo(const Color &col, time_ns duratio = time_from_sec_f(0.25f));
void SetFade(const Color &col);

//
struct Player {
	Vector2 pos{0, 0};
	Vector2 spd{0, 0};
	float angle{0};

	std::string msg;
	time_ns msg_delay{0};

	bool ai{true};
	float ai_angle{0};
	time_ns ai_shot_delay{0};
};

std::array<Player, 4> players;
std::array<std::shared_ptr<InputDevice>, 4> gamepads;

int AnyButtonPressed() {
	for (int i = 0; i < gamepads.size(); ++i)
		if (gamepads[i]->WasButtonPressed(Button0))
			return i;
	return -1;
}

std::array<Color, 4> players_color = {Color(238.f / 255.f, 94.f / 255.f, 255.f / 255.f), Color(251.f / 255.f, 220.f / 255.f, 46.f / 255.f), Color(32.f / 255.f, 255.f / 255.f, 63.f / 255.f), Color(36.f / 255.f, 227.f / 255.f, 255.f / 255.f)};

Vector2 AngleToDirection(float angle) {
	angle = -angle + Deg(90.f);
	return {Sin(angle), Cos(angle)};
}

float DirectionToAngle(Vector2 dir) {
	float angle = atan2(dir.y, dir.x);
	return angle;
}

time_ns GetAIDelay() { return Rand(ai_max_delay - ai_min_delay) + ai_min_delay; }

static const char *player_0[] = {"@data:drone_0.png", "@data:drone_1.png", "@data:drone_2.png", "@data:drone_3.png"};

float aaa = 0;

void DrawText2DCentered(float x, float y, const std::string &text, float size = 16, Color color = Color::White, const char *font_path = "") {
	auto rect = g_plus.get().GetTextRect(text, size, font_path);
	g_plus.get().Text2D(x - rect.GetWidth() / 2, y + rect.GetHeight() / 2, text, size, color, font_path);
}

void SetPlayerMessage(Player &player, const char *msg) {
	player.msg = msg;
	player.msg_delay = time_from_sec(2);
}

void DrawPlayerMessage(Player &player) {
	if (player.msg_delay > 0) {
		float x = player.pos.x, y = player.pos.y + 38.f;
		auto alpha = Clamp<float>(float(player.msg_delay) / time_from_sec_f(0.2));

		DrawText2DCentered(x, y, player.msg.c_str(), 18.f, Color(0, 0, 0, 0.5f * alpha), "@data:komikax.ttf");
		DrawText2DCentered(x - 2, y + 2, player.msg.c_str(), 18.f, Color(1, 1, 1, 1 * alpha), "@data:komikax.ttf");
		player.msg_delay -= GetLastFrameDuration();
	}
}

void DrawPlayer(int idx, const Color &col) {
	auto &player = players[idx];

	auto shots = GetPlayerShoots(idx);

	if (shots.size() > 0) {
		g_plus.get().Sprite2D(player.pos.x, player.pos.y, 160.f, "@data:drone_buffer.png", players_color[idx]);
		g_plus.get().Text2D(player.pos.x - 6.f, player.pos.y - 12.f, format("%1").arg(shots.size()), 32.f, players_color[idx], "@data:impact.ttf");
	} else {
		g_plus.get().Sprite2D(player.pos.x, player.pos.y, 160.f, "@data:drone.png", players_color[idx]);
	}

	if (shots.size() > 0) {
		auto &shot = shoots[shots[0]];

		Color tgt_col;
		if (shot.player_seq_idx == 3) {
			tgt_col = Color::Red;
		} else {
			int tgt_idx = shot.player_seq[shot.player_seq_idx + 1];
			tgt_col = players_color[tgt_idx];
		}

		auto dir = AngleToDirection(player.angle);
		g_plus.get().RotatedSprite2D(player.pos.x, player.pos.y, player.angle - Deg(90.f), 160.f, "@data:drone_arrow.png", tgt_col);
	}
}

void PlayerFireShot(int player_idx, int idx) {
	auto &player = players[player_idx];
	auto &shot = shoots[idx];

	auto dir = AngleToDirection(player.angle);
	shot.pos = player.pos + dir * player_radius; // prevent self collision
	shot.spd = dir * shoot_speed;
	shot.hold_until = 0;
	player.spd += shot.spd * player_decoy_coef;
	__ASSERT__(shot.player_seq_idx < 4);
	shot.player_seq_idx++;

	g_plus.get().GetMixer()->Start(*piout);
}

Vector2 GetShootNextTargetPos(const Shoot &shot) {
	if ((shot.player_seq_idx + 1) == 4) // sequence end: shot alien!
		return Vector2(width / 2, 0);

	int tgt_idx = shot.player_seq[shot.player_seq_idx + 1];
	return players[tgt_idx].pos;
}

void UpdatePlayer(int idx) {
	auto &player = players[idx];

	player.pos += player.spd;
	player.spd *= player_damping;

	if (player.ai) {
		auto shots = GetPlayerShoots(idx);

		if (shots.size() > 0) {
			auto &shot = shoots[shots[0]];
			auto tgt_pos = GetShootNextTargetPos(shot);

			auto dir = (tgt_pos - player.pos).Normalized();
			player.ai_angle = DirectionToAngle(dir) + FRRand(-ai_precision_delta, ai_precision_delta);
			player.angle += (player.ai_angle - player.angle) * ai_aiming_speed;

			player.ai_shot_delay -= GetLastFrameDuration();

			if (player.ai_shot_delay < 0) {
				PlayerFireShot(idx, shots[0]);
				player.ai_shot_delay = GetAIDelay();
			}
		}
	}
}

void PlayerCollidePlayfield(Player &player) {
	constexpr auto playfield_padding_augmented = playfield_padding + player_radius;

	bool sfx = false;

	if (player.pos.x > (width - playfield_padding_augmented)) {
		if (player.spd.x > 0)
			player.spd.x *= -player_to_wall_collision_damping;
		sfx = true;
	}
	if (player.pos.x < playfield_padding_augmented) {
		if (player.spd.x < 0)
			player.spd.x *= -player_to_wall_collision_damping;
		sfx = true;
	}
	if (player.pos.y > (height - playfield_padding_augmented * 3.5f)) {
		if (player.spd.y > 0)
			player.spd.y *= -player_to_wall_collision_damping;
		sfx = true;
	}
	if (player.pos.y < playfield_padding_augmented * 3.5f) {
		if (player.spd.y < 0)
			player.spd.y *= -player_to_wall_collision_damping;
		sfx = true;
	}

	if (sfx)
		g_plus.get().GetMixer()->Start(*bidon);
}

void PlayerCollidePlayer(Player &a, Player &b) {
	auto d = b.pos - a.pos;
	auto l = d.Len();

	if (l < player_radius * 2) {
		auto k = (player_radius * 2 - l) * player_to_player_collision_damping;
		auto v = d * (k / l);

		b.spd += v;
		a.spd -= v;

		g_plus.get().GetMixer()->Start(*bidon);
	}
}

void UpdatePlayersCollision() {
	for (size_t i = 0; i < players.size(); ++i)
		for (size_t j = 0; j < players.size(); ++j)
			if (i != j)
				PlayerCollidePlayer(players[i], players[j]);

	for (auto &player : players)
		PlayerCollidePlayfield(player);
}

void UpdatePlayerInputs(int idx, InputDevice &device) {
	auto &player = players[idx];

	if (!player.ai) {
		Vector2 v{device.GetValue(InputAxisX), device.GetValue(InputAxisY)};
		auto l = v.Len();

		if (l > 0.25f) {
			v /= l;
			player.angle = atan2(v.y, v.x);
		}

		if (gamepads[idx]->WasButtonPressed(Button0)) {
			auto shots = GetPlayerShoots(idx);
			if (shots.size() > 0)
				PlayerFireShot(idx, shots[0]);
		}
	}
}

//
std::function<bool()> game_state, next_game_state;

//
bool GameInit();
bool GameLoop();
bool Title();

void ShootAtTarget(Shoot &shoot, const Vector2 &tgt) {
	shoot.spd = (tgt - shoot.pos).Normalized() * shoot_speed;
	shoot.hold_until = 0;
}

void InitShoot(Shoot &shoot) {
	for (int i = 0; i < 4; ++i)
		shoot.player_seq[i] = i;

	for (int i = 0; i < 4; ++i) {
		int a = Rand(4), b = Rand(4);
		auto tmp = shoot.player_seq[a];
		shoot.player_seq[a] = shoot.player_seq[b];
		shoot.player_seq[b] = tmp;
	}

	shoot.player_seq_idx = 0;
	shoot.pos = Vector2(width / 2, 0);
	shoot.hold_until = 0;

	ShootAtTarget(shoot, players[shoot.player_seq[shoot.player_seq_idx]].pos);
}

std::vector<int> GetPlayerShoots(int idx) {
	std::vector<int> shoot_idxs;
	for (size_t i = 0; i < shoots.size(); ++i) {
		auto &shoot = shoots[i];
		if (shoot.hold_until && (shoot.player_seq[shoot.player_seq_idx] == idx))
			shoot_idxs.push_back(i);
	}
	return shoot_idxs;
}

//
static std::string earth_msg;
static time_ns earth_msg_duration{0};

void SetEarthMessage(const char *msg) {
	earth_msg = msg;
	earth_msg_duration = time_from_sec(2);
}

Vector2 GetEarthPos() { return Vector2(width / 2.f, height - 120.f); }

void DrawEarthMessage() {
	if (earth_msg_duration > 0) {
		auto pos = GetEarthPos();
		auto alpha = Clamp<float>(float(earth_msg_duration) / time_from_sec_f(0.2));

		DrawText2DCentered(pos.x, pos.y, earth_msg.c_str(), 64.f, Color(0, 0, 0, 0.75f * alpha), "@data:komikax.ttf");
		DrawText2DCentered(pos.x - 8, pos.y + 8, earth_msg.c_str(), 64.f, Color(1, 1, 1, 1 * alpha), "@data:komikax.ttf");
		earth_msg_duration -= GetLastFrameDuration();
	}
}

//
static std::string alien_msg;
static time_ns alien_msg_duration{0};

void SetAlienMessage(const char *msg) {
	alien_msg = msg;
	alien_msg_duration = time_from_sec(2);
}

Vector2 GetAlienPos() {
	float x = width / 2.f, y = 60.f;

	auto offset = FRRand(-4.f, 4.f);
	x += offset;
	y += offset;

	return Vector2(x, y);
}

void DrawAlienMessage() {
	if (alien_msg_duration > 0) {
		auto pos = GetAlienPos();
		auto alpha = Clamp<float>(float(alien_msg_duration) / time_from_sec_f(0.2));

		DrawText2DCentered(pos.x, pos.y, alien_msg.c_str(), 64.f, Color(0, 0, 0, 0.75f * alpha), "@data:komikax.ttf");
		DrawText2DCentered(pos.x - 8, pos.y + 8, alien_msg.c_str(), 64.f, Color(1, 0, 0, 1 * alpha), "@data:komikax.ttf");
		alien_msg_duration -= GetLastFrameDuration();
	}
}

//
void SpawnBloodSplatFX(const Vector2 &pos, const char *path) {
	for (int i = 0; i < 3; ++i)
		SpawnFX(pos.x + FRRand(-width * 0.5f, width * 0.5f), pos.y + FRRand(-20.f, 20.f), path, FRRand(200, 600), FRRand(0, 2), time_from_sec(1), time_from_sec_f(FRRand(0, 1)));
}

//
void UpdateShoot(int idx) {
	auto &shoot = shoots[idx];

	bool out_of_bound = false;

	if (shoot.hold_until == 0) {
		shoot.pos += shoot.spd;

		// detect drone collision
		for (int i = 0; i < 4; ++i) {
			auto &player = players[i];
			if (Vector2::Dist(shoot.pos, player.pos) < (shoot_radius + player_radius)) {
				bool correct_transfer = true;

				if (shoot.player_seq_idx == 4) // alien expected
					correct_transfer = false;
				else
					correct_transfer = i == shoot.player_seq[shoot.player_seq_idx];

				if (correct_transfer) {
					shoot.hold_until = shoot_hold_duration;
					player.spd += shoot.spd * shoot_to_player_transfer_coef;

					SpawnFX(player.pos.x, player.pos.y, "@data:fx_donut.png", 200.f, 0, time_from_sec_f(0.2), 0, Color(1, 1, 1, 0.75f), 8.f);
				}
			}
		}

		// detect out of playfield
		bool could_hit_alien = false;

		if (shoot.pos.x < -shoot_radius) {
			out_of_bound = true;
		} else if (shoot.pos.x > width + shoot_radius) {
			out_of_bound = true;
		} else if (shoot.pos.y < -shoot_radius) {
			could_hit_alien = true;
			out_of_bound = true;
		} else if (shoot.pos.y > height + shoot_radius) {
			out_of_bound = true;
		}

		if (out_of_bound == true) {
			if (shoot.player_seq_idx == 0) { // initial alien shot
				SetAlienMessage("Human escape!");
				g_plus.get().GetMixer()->Start(*piout);
			} else if (shoot.player_seq_idx == 4) { // last human shot
				if (could_hit_alien) {
					SetPlayerMessage(players[shoot.player_seq[3]], "Humanity hero!");
					SetAlienMessage("Sufffering!");
					SpawnBloodSplatFX(GetAlienPos(), "@data:alien_blood.png");
					ShakeBG(10.f);
					alien_health -= 5;
					g_plus.get().GetMixer()->Start(*tako);
				} else {
					SetPlayerMessage(players[shoot.player_seq[3]], "You drunkard!");
					SetAlienMessage("Alien missed!");
					SetEarthMessage("Genocide!");
					SpawnBloodSplatFX(GetEarthPos(), "@data:human_blood.png");
					ShakeBG(10.f);
					human_health -= 10;
					g_plus.get().GetMixer()->Start(*explosion);
				}
			} else {
				SetPlayerMessage(players[shoot.player_seq[shoot.player_seq_idx - 1]], "Chain breaker!");
				SpawnBloodSplatFX(GetEarthPos(), "@data:human_blood.png");
				SetEarthMessage("Cataclysm!");
				ShakeBG(4.f);
				human_health -= 5;
				g_plus.get().GetMixer()->Start(*explosion);
			}
		}
	}

	if (out_of_bound)
		shoots.erase(shoots.begin() + idx);
}

void UpdateShoots() {
	for (int i = 0; i < shoots.size(); ++i)
		UpdateShoot(i);
}

void DrawShoot(Shoot &shoot) {
	if (shoot.hold_until == 0)
		g_plus.get().RotatedSprite2D(shoot.pos.x, shoot.pos.y, DirectionToAngle(shoot.spd), 150.f, "@data:drone_shoot.png", Color::White, 93.f / 150.f, 0.5f);
}

void DrawShoots() {
	for (auto &shoot : shoots)
		DrawShoot(shoot);
}

//
void SpawnShoot() {
	SetAlienMessage("Attack!");
	shoots.emplace_back();
	InitShoot(shoots.back());
}

//
time_ns next_shoot_delay = 0;

void HeuristicSpawnShoot() {
	next_shoot_delay -= GetLastFrameDuration();
	if (next_shoot_delay < 0) {
		next_shoot_delay = time_from_sec_f(FRRand(1.f, 3.5f));
		SpawnShoot();
	}
}

//
void DrawHealthBar(float x, float y, int health) {
	int idx = Clamp<int>(((health + 9) / 10), 0, 10) * 10;
	auto path = format("@data:life_bar_%1.png").arg(idx).str();
	g_plus.get().Image2D(x, y, 1, path.c_str());
}

void DrawUI() {
	g_plus.get().Sprite2D(80, height - 200, 120.f, "@data:alien_avatar.png");
	g_plus.get().Sprite2D(width - 80, height - 200, 120.f, "@data:human_avatar.png");

	DrawHealthBar(80 + 40, height - 200, alien_health);
	DrawHealthBar(width - 80 - 40 - 230, height - 200, human_health);

	for (auto &player : players)
		DrawPlayerMessage(player);

	DrawEarthMessage();
	DrawAlienMessage();
}

float bg_shake_strength = 0.f;

void ShakeBG(float strength) { bg_shake_strength = strength; }

void DrawBG() {
	float shake_offx = FRRand(-1.f, 1.f), shake_offy = FRRand(-1.f, 1.f);
	g_plus.get().Image2D(shake_offx * bg_shake_strength, shake_offy * bg_shake_strength, 1, "@data:space_bg.jpg");
	bg_shake_strength *= 0.95f;

	float a = time_to_sec_f(g_plus.get().GetClock());
	float alien_x = Cos(a * 0.75f) * 25.f;

	g_plus.get().Image2D(alien_x, -(100 - alien_health), 1, "@data:tentacles.png");
}

struct FX {
	std::string img;
	Vector2 pos;
	float size;
	float rotation;
	time_ns delay;
	time_ns duration;
	Color color;
	float size_spd;
};

std::vector<FX> fxs;

void DrawFXs() {
	auto k_fade = time_from_sec_f(0.25f);

	for (auto &fx : fxs) {
		if (fx.delay > 0) {
			fx.delay -= GetLastFrameDuration();
		} else {
			auto alpha = Clamp<float>(float(fx.duration) / k_fade);
			auto col = fx.color;
			col.a *= alpha;
			g_plus.get().RotatedSprite2D(fx.pos.x, fx.pos.y, fx.rotation, fx.size, fx.img.c_str(), col);
			fx.size += fx.size_spd;
			fx.duration -= GetLastFrameDuration();
		}
	}

	fxs.erase(std::remove_if(fxs.begin(), fxs.end(), [](const FX &fx) { return fx.duration < 0; }), fxs.end());
}

void SpawnFX(float x, float y, const char *img, float size, float rotation, time_ns duration, time_ns delay, Color color, float size_spd) {
	FX fx;
	fx.img = img;
	fx.pos = Vector2(x, y);
	fx.size = size;
	fx.rotation = rotation;
	fx.delay = delay;
	fx.duration = duration;
	fx.color = color;
	fx.size_spd = size_spd;
	fxs.push_back(fx);
}

//
Color fade_color(0, 0, 0, 0), fade_to;
time_ns fade_duration, fade_t;

void FullscreenQuad(const Color &color) {
	g_plus.get().Quad2D(0, 0, 0, height, width, height, width, 0, color, color, color, color);
}

bool IsFading() { return fade_duration > 0; }

void FadeTo(const Color &col, time_ns duration) {
	fade_to = col;
	fade_t = fade_duration = duration;
}

void SetFade(const Color &col) { fade_color = col; }

void DrawFade() {
	Color col;

	if (fade_duration > 0) {
		auto k = time_to_sec_f(fade_duration) / time_to_sec_f(fade_t);
		col = fade_color * k + fade_to * (1.f - k);
		fade_duration -= GetLastFrameDuration();
	} else {
		col = fade_color = fade_to;
	}

	if (col.a)
		FullscreenQuad(col);
}

//
std::string game_over_img;

void DrawGameOver() {
	g_plus.get().Image2D(0, 0, 1, "@data:default_screen.jpg");
	g_plus.get().Image2D(0, 550, 1, game_over_img.c_str());
}

bool GameOverFade() {
	DrawGameOver();

	if (IsFading())
		return false;

	next_game_state = &Title;
	return true;
}

bool GameOver() {
	DrawGameOver();

	if (!IsFading() && AnyButtonPressed() != -1) {
		SetFade(Color(0, 0, 0, 0));
		FadeTo(Color::Black, time_from_sec(1));
		next_game_state = &GameOverFade;
		return true;
	}
	return false;
}

//
void GameLoopCommon() {
	DrawBG();

	UpdatePlayersCollision();

	for (size_t i = 0; i < players.size(); ++i) {
		UpdatePlayerInputs(i, *gamepads[i]);
		UpdatePlayer(i);
		DrawPlayer(i, players_color[i]);
	}

	HeuristicSpawnShoot();
	UpdateShoots();
	DrawShoots();

	DrawFXs();
	DrawUI();
}

bool attract_mode{false};
time_ns attract_mode_duration{0};

bool GameInit() {
	fxs.clear();
	shoots.clear();

	earth_msg_duration = 0;
	alien_msg_duration = 0;

	for (auto &player : players) {
		player.pos = {FRRand(100, 620), FRRand(400, 800)};
		player.spd = {FRRand(-0.1f, 0.1f), FRRand(-0.1f, 0.1f)};
		player.angle = FRand(Deg(360.f));
		player.ai_shot_delay = GetAIDelay();
		player.msg_delay = 0;
	}

	human_health = 100;
	alien_health = 100;

	next_game_state = &GameLoop;
	next_shoot_delay = time_from_sec(3);

	SetAlienMessage("GraaawwwR!");

	SetFade(Color::Black);
	FadeTo(Color(0, 0, 0, 0));

	attract_mode = false;
	return true;
}

bool AttractMode() {
	for (auto &player : players)
		player.ai = true;

	GameInit();

	attract_mode = true;
	attract_mode_duration = time_from_sec(20);

	SetFade(Color::White);
	FadeTo(Color(1, 1, 1, 0));
	return true;
}

void GameDebugKeys() {
	if (g_plus.get().KeyDown(KeyF1))
		human_health = 0;
	if (g_plus.get().KeyDown(KeyF2))
		alien_health = 0;
}

bool GameLoop() {
	if (attract_mode) {
		attract_mode_duration -= GetLastFrameDuration();
		if (attract_mode_duration < 0 || human_health < 10 || alien_health < 10 || (AnyButtonPressed() != -1)) {
			next_game_state = Title;
			return true;
		}
	}

	GameLoopCommon();
	GameDebugKeys();

	if (alien_health <= 0) {
		SetFade(Color::Blue);
		FadeTo(Color(1, 0, 0, 0), time_from_sec(3));
		game_over_img = "@data:victory_text.png";
		next_game_state = &GameOver;
		return true;
	} else if (human_health <= 0) {
		SetFade(Color::Red);
		FadeTo(Color(1, 0, 0, 0), time_from_sec(3));
		game_over_img = "@data:game_over_text.png";
		next_game_state = &GameOver;
		return true;
	}

	if (attract_mode)
		if ((attract_mode_duration % time_from_sec_f(1)) > time_from_sec_f(0.5f))
			g_plus.get().Image2D(0, 80, 1, "@data:press_any_button_text.png");

	return false;
}

//
bool DetectGameStart();

time_ns how_to_play_time;
bool how_to_play_can_start_game;
std::function<bool()> how_to_play_branch_to;

bool HowToPlayWaitFade() {
	g_plus.get().Image2D(0, 0, 1, "@data:default_screen.jpg");
	g_plus.get().Image2D(0, 0, 1, "@data:how_to_play_02.png");

	if (!IsFading()) {
		next_game_state = how_to_play_branch_to;
		return true;
	}
	return false;
}

bool HowToPlayScreen() {
	g_plus.get().Image2D(0, 0, 1, "@data:default_screen.jpg");

	if (how_to_play_time > time_from_sec(8)) {
		g_plus.get().Image2D(0, 0, 1, "@data:how_to_play_02.png");
		if (AnyButtonPressed() != -1)
			how_to_play_time = time_from_sec(16);
	} else {
		g_plus.get().Image2D(0, 0, 1, "@data:how_to_play_01.png");
		if (AnyButtonPressed() != -1)
			how_to_play_time = time_from_sec(8);
	}

	if (how_to_play_time > time_from_sec(16)) {
		SetFade(Color(0, 0, 0, 0));
		FadeTo(Color::Black, time_from_sec_f(0.5f));
		next_game_state = &HowToPlayWaitFade;
		return true;
	}

	how_to_play_time += GetLastFrameDuration();
	return false;
}

bool HowToPlay() {
	how_to_play_time = 0;
	SetFade(Color::White);
	FadeTo(Color(1, 1, 1, 0));
	next_game_state = &HowToPlayScreen;
	return true;
}

//
time_ns join_delay;

void DrawPlayerJoinScreen() {
	g_plus.get().Image2D(0, 0, 1, "@data:default_screen.jpg");
	g_plus.get().Image2D(0, 0, 1, "@data:join_overlay.png");

	FullscreenQuad(Color(0, 0, 0, 0.75f));

	DrawText2DCentered(width / 4, height / 4 - 40.f, players[0].ai ? "CPU" : "P1", 128.f, players_color[0], "@data:impact.ttf");
	DrawText2DCentered(width / 4, height / 4 * 3 - 40.f, players[1].ai ? "CPU" : "P2", 128.f, players_color[1], "@data:impact.ttf");
	DrawText2DCentered(width / 4 * 3, height / 4 - 40.f, players[2].ai ? "CPU" : "P3", 128.f, players_color[2], "@data:impact.ttf");
	DrawText2DCentered(width / 4 * 3, height / 4 * 3 - 40.f, players[3].ai ? "CPU" : "P4", 128.f, players_color[3], "@data:impact.ttf");

	DrawText2DCentered(width / 4, height / 4 - 120.f, players[0].ai ? "Join now!" : "Get ready!", 48.f, players_color[0], "@data:impact.ttf");
	DrawText2DCentered(width / 4, height / 4 * 3 - 120.f, players[1].ai ? "Join now!" : "Get ready!", 48.f, players_color[1], "@data:impact.ttf");
	DrawText2DCentered(width / 4 * 3, height / 4 - 120.f, players[2].ai ? "Join now!" : "Get ready!", 48.f, players_color[2], "@data:impact.ttf");
	DrawText2DCentered(width / 4 * 3, height / 4 * 3 - 120.f, players[3].ai ? "Join now!" : "Get ready!", 48.f, players_color[3], "@data:impact.ttf");

	DrawText2DCentered(width / 2, height / 2 - 160.f, format("%1").arg(time_to_sec(join_delay)), 190.f, Color::White, "@data:komikax.ttf");
}

bool WaitJoinFadeOut() {
	DrawPlayerJoinScreen();

	if (!IsFading()) {
		next_game_state = &HowToPlay;
		return true;
	}

	return false;
}

bool PlayerJoinScreen() {
	DrawPlayerJoinScreen();

	int player_idx = AnyButtonPressed();
	if (player_idx != -1) {
		if (players[player_idx].ai) {
			g_plus.get().GetMixer()->Start(*beep);
			players[player_idx].ai = false; // player controlled
		} else {
			join_delay -= time_from_sec(1);
		}
	}

	bool join_done = true;
	for (auto &player : players)
		if (player.ai)
			join_done = false;

	join_delay -= GetLastFrameDuration();
	if (join_delay < 0) {
		join_delay = 0;
		join_done = true;
	}

	if (join_done) {
		SetFade(Color(0, 0, 0, 0));
		FadeTo(Color::Black, time_from_sec(1));
		next_game_state = &WaitJoinFadeOut;
		return true;
	}
	return false;
}

void InitJoinScreen() {
	how_to_play_branch_to = &GameInit;
	how_to_play_can_start_game = false;
	join_delay = time_from_sec(10);
}

//
bool DetectGameStart() {
	int player_idx = AnyButtonPressed();

	if (player_idx != -1) {
		g_plus.get().GetMixer()->Start(*beep);

		for (auto &player : players)
			player.ai = true; // CPU controlled

		players[player_idx].ai = false; // player controlled

		InitJoinScreen();
		next_game_state = &PlayerJoinScreen;

		SetFade(Color::White);
		FadeTo(Color(1, 1, 1, 0));
		return true;
	}

	return false;
}

//
int intro_seq;
time_ns intro_seq_delay;

time_ns intro_t;

Vector2 Lerp(const Vector2 &a, const Vector2 &b, float t) { return (b - a) * t + a; }

void DrawTitle() {
	g_plus.get().Image2D(0, 0, 1, "@data:intro_bg.jpg");

	auto t_earth = Clamp<float>(time_to_sec_f(intro_t) / 18.f);
	auto earth_pos = Lerp(Vector2(0, -400), Vector2(0, 0), t_earth);

	g_plus.get().Image2D(earth_pos.x, earth_pos.y, 1, "@data:intro_earth.png");
	if (intro_seq >= 4)
		g_plus.get().Image2D(width - 455, height - 520, 1, "@data:intro_alien.png");

	if (intro_seq > 0)
		g_plus.get().Image2D(0, height / 2.f - 140.f, 1.f, format("@data:intro_text0%1.png").arg(Clamp(intro_seq, 1, 4)));

	if ((intro_t % time_from_sec_f(1)) > time_from_sec_f(0.5f))
		g_plus.get().Image2D(0, 80, 1, "@data:press_any_button_text.png");

	intro_t += GetLastFrameDuration();
}

bool title_loop_attract{true};

bool TitleWaitFadeOut() {
	if (DetectGameStart())
		return true;

	DrawTitle();

	if (!IsFading()) {
		next_game_state = title_loop_attract ? &AttractMode : &HowToPlay;
		title_loop_attract = !title_loop_attract;
		how_to_play_can_start_game = true;
		return true;
	}
	return false;
}

bool IntroAndTitleScreen() {
	if (DetectGameStart())
		return true;

	DrawTitle();

	intro_seq_delay -= GetLastFrameDuration();

	if (intro_seq_delay < 0) {
		++intro_seq;

		if (intro_seq == 5) {
			SetFade(Color(0, 0, 0, 0));
			FadeTo(Color::Black, time_from_sec(2));
			next_game_state = &TitleWaitFadeOut;
			return true;
		} else if (intro_seq == 4) {
			intro_seq_delay = time_from_sec(6);
			SetFade(Color::White);
			FadeTo(Color(1, 1, 1, 0), time_from_sec(1));
		} else {
			intro_seq_delay = time_from_sec(3);
		}
	}
	return false;
}

//
bool Title() {
	SetFade(Color(0, 0, 0, 1));
	FadeTo(Color(0, 0, 0, 0), time_from_sec(6));

	intro_t = 0;
	intro_seq = 0;
	intro_seq_delay = time_from_sec(6);

	next_game_state = &IntroAndTitleScreen;
	how_to_play_branch_to = &Title;
	how_to_play_can_start_game = false;
	return true;
}

//
bool SetupGamepads() {
	gamepads[0] = g_input_system.get().GetDevice("xinput.port0");
	gamepads[1] = g_input_system.get().GetDevice("xinput.port1");
	gamepads[2] = g_input_system.get().GetDevice("xinput.port2");
	gamepads[3] = g_input_system.get().GetDevice("xinput.port3");

	if (!gamepads[0] || !gamepads[1] || !gamepads[2] || !gamepads[3]) {
		error("No XInput support, falling back to keyboard");
		for (int i = 0; i < 4; ++i)
			gamepads[i] = g_input_system.get().GetDevice("keyboard");
	}
	return true;
}

//
int main(int narg, const char **args) {
	Init();
	LoadPlugins();

	if (!g_plus.get().RenderInit(720, 1280, 4) || !g_plus.get().AudioInit())
		return 1;

	g_plus.get().SetWindowTitle("Invasion of the Tako Nation - Harfang 3D");

	if (!SetupGamepads())
		return 1;

#if _DEBUG
	g_plus.get().MountAs("d:/gs-users/ggj2018/data", "@data:");
#else
	g_plus.get().MountAs("./data", "@data:");
#endif
	g_plus.get().SetBlend2D(BlendAlpha);

	if (!LoadSoundFXs())
		return 1;

	g_plus.get().GetMixer()->Stream("@data:zik.ogg", Mixer::RepeatState);

	game_state = &Title;

	while (!g_plus.get().IsAppEnded()) {
		g_plus.get().Clear(Color::Black);

		if (game_state())
			game_state = next_game_state;

		DrawFade();

		g_plus.get().Flip();
		g_plus.get().EndFrame();
		g_plus.get().UpdateClock();
	}

	exit(0);

	g_plus.get().RenderUninit();
	g_plus.get().AudioUninit();

	Uninit();
	return 0;
}
