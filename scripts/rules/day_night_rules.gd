# DayNightRules — pure maths for the day/night cycle (D-110): where the sun is at a given hour, how far into
# night we are, and what hour sleeping skips to. No nodes, no rendering; the caller passes the tuning Dictionary
# (data/tuning/day_night.json). Depends on: nothing.
class_name DayNightRules
extends RefCounted


# Hour 0..24 after `seconds` of play, starting at start_hour and running one full day every day_seconds.
static func hour_at(seconds: float, day_seconds: float, start_hour: float) -> float:
	if day_seconds <= 0.0:
		return start_hour
	return fposmod(start_hour + seconds / day_seconds * 24.0, 24.0)


# Advances `hour` by `delta` real seconds.
static func advance(hour: float, delta: float, day_seconds: float) -> float:
	if day_seconds <= 0.0:
		return hour
	return fposmod(hour + delta / day_seconds * 24.0, 24.0)


# The sun's elevation in degrees: it climbs to sun_max_elevation_deg at midday and is NEGATIVE at night, where it
# falls to -moon_max_elevation_deg at the middle of the night (that mirrored arc is where the moon is).
static func sun_elevation(hour: float, t: Dictionary) -> float:
	var rise := float(t.get("sunrise_hour", 6.5))
	var set_h := float(t.get("sunset_hour", 19.5))
	if hour >= rise and hour <= set_h:
		var day_len := maxf(set_h - rise, 0.001)
		return float(t.get("sun_max_elevation_deg", 56.0)) * sin(PI * (hour - rise) / day_len)
	var night_len := maxf(24.0 - (set_h - rise), 0.001)
	var since := fposmod(hour - set_h, 24.0)
	return -float(t.get("moon_max_elevation_deg", 44.0)) * sin(PI * since / night_len)


# 0 in full daylight, 1 in full night, blending through dusk and dawn.
static func night_factor(hour: float, t: Dictionary) -> float:
	return clampf(inverse_lerp(4.0, -4.0, sun_elevation(hour, t)), 0.0, 1.0)


# 0 except around sunrise and sunset, where the sky and the light go orange.
static func dusk_factor(hour: float, t: Dictionary) -> float:
	var e := sun_elevation(hour, t)
	return clampf(1.0 - absf(e) / 9.0, 0.0, 1.0)


static func is_night(hour: float, t: Dictionary) -> bool:
	return night_factor(hour, t) > 0.5


# How many in-game hours from `hour` forward to wake_hour (always > 0, so sleeping never goes backwards).
static func hours_until(hour: float, wake_hour: float) -> float:
	var d := fposmod(wake_hour - hour, 24.0)
	return 24.0 if d < 0.01 else d


static func phase_name(hour: float, t: Dictionary) -> String:
	var e := sun_elevation(hour, t)
	if e > 25.0:
		return "day"
	if e > 4.0:
		return "morning" if hour < 12.0 else "afternoon"
	if e > -4.0:
		return "dawn" if hour < 12.0 else "dusk"
	return "night"


# "07:30" from an hour.
static func clock(hour: float) -> String:
	var h := int(hour) % 24
	var m := int(fposmod(hour, 1.0) * 60.0)
	return "%02d:%02d" % [h, m]
