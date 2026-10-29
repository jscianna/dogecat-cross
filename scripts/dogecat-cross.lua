-- Dogecat Cross: frogger-style badge game
-- Hop the cat-on-doge from the curb to the goal. Traffic speeds up each round.

local g = badge.gfx
local input = badge.input
local kv = badge.storage.kv

local W = g.width()
local H = g.height()

local HUD = 16
local RH = 16
local CW = 16
local ROWS = (H - HUD) // RH
local COLS = W // CW
local START_ROW = ROWS - 1
local START_COL = COLS // 2
local CAR_H = 10
local HIT = 4

local ROAD = g.color(26, 28, 38)
local DASH = g.color(78, 82, 98)
local GRASS = g.color(22, 96, 54)
local GRASS_DK = g.color(14, 64, 36)
local TUFT = g.color(78, 186, 92)
local WALK = g.color(58, 54, 72)
local WALK_LT = g.color(74, 70, 90)
local GOAL_L = g.color(46, 16, 82)
local GOAL_R = g.color(12, 58, 46)
local DOGE = g.color(232, 182, 68)
local DOGE_DK = g.color(168, 112, 36)
local DOGE_LT = g.color(255, 214, 130)
local CAT = g.color(62, 60, 76)
local CAT_LT = g.color(118, 114, 136)
local NOSE = g.color(42, 32, 36)
local WINDOW = g.color(198, 232, 255)
local LAMP = g.color(255, 244, 186)

local CAR_COLORS = {
  g.color(255, 196, 48),
  g.SOLANA_PURPLE,
  g.color(255, 96, 72),
  g.SOLANA_TEAL,
  g.color(96, 176, 255),
  g.SOLANA_MAGENTA,
  g.color(255, 148, 40),
  g.color(130, 220, 96),
  g.color(236, 236, 244),
}

-- First lanes are the ones you meet at the curb: slower, wider gaps.
-- row, dir, speed, width, gap
local SPECS = {
  { 11,  1, 46, 62, 104 },
  { 10, -1, 60, 34, 76 },
  { 9,   1, 72, 30, 68 },
  { 7,  -1, 66, 40, 86 },
  { 6,   1, 44, 72, 108 },
  { 5,  -1, 86, 28, 62 },
  { 3,   1, 78, 36, 74 },
  { 2,  -1, 98, 26, 56 },
  { 1,   1, 112, 32, 60 },
}

local SELECT = "SELECT"
local CANCEL = "CANCEL"

local mode = "title"
local t = 0
local score = 0
local best = 0
local round = 1
local progress = START_ROW
local clear_t = 0
local score_flash = 0
local got_best = false
local hold_key = nil
local hold_t = 0
local lanes = {}
local lane_at = {}

local player = {
  col = START_COL,
  row = START_ROW,
  face = 1,
  hop = 0,
}

local function wrap_mod(x, total)
  x = x % total
  if x < 0 then x = x + total end
  return x
end

local function build_lanes()
  lanes = {}
  lane_at = {}
  for i, spec in ipairs(SPECS) do
    local row, dir, speed, w, gap = spec[1], spec[2], spec[3], spec[4], spec[5]
    local span = w + gap
    local n = math.ceil((W + span) / span)
    local total = n * span
    local phase = (i * 67) % span
    local cars = {}
    for c = 1, n do
      cars[c] = { x = wrap_mod(phase + (c - 1) * span, total) }
    end
    local lane = {
      row = row,
      dir = dir,
      speed = speed,
      w = w,
      gap = gap,
      color = CAR_COLORS[((i - 1) % #CAR_COLORS) + 1],
      cars = cars,
    }
    lanes[i] = lane
    lane_at[row] = lane
  end
end

local function lane_total(lane)
  return (lane.w + lane.gap) * #lane.cars
end

local function speed_mul()
  local m = 1 + (round - 1) * 0.16
  if m > 2.2 then m = 2.2 end
  return m
end

local function spawn_player()
  player.col = START_COL
  player.row = START_ROW
  player.face = 1
  player.hop = 0
  progress = START_ROW
end

local function commit_best()
  if score > best then
    got_best = true
    best = score
    kv.set("best", tostring(best))
  end
end

local function start_game()
  score = 0
  round = 1
  clear_t = 0
  score_flash = 0
  got_best = false
  hold_key = nil
  hold_t = 0
  spawn_player()
  mode = "play"
  badge.led.gradient(0, 0.2, 0.45)
  badge.led.gradient(1, 0.85, 0.45)
  badge.led.show()
  badge.log("play")
end

local function die()
  mode = "dead"
  hold_key = nil
  commit_best()
  badge.led.pulse(255, 42, 48, 700)
  badge.log("splat")
end

local function try_hop(key)
  if mode ~= "play" or clear_t > 0 then return end
  local dc, dr = 0, 0
  if key == "left" then dc = -1
  elseif key == "right" then dc = 1
  elseif key == "up" then dr = -1
  elseif key == "down" then dr = 1
  else return end
  local nc = player.col + dc
  local nr = player.row + dr
  if nc < 0 or nc >= COLS or nr < 0 or nr >= ROWS then return end
  player.col = nc
  player.row = nr
  if dc < 0 then player.face = -1
  elseif dc > 0 then player.face = 1 end
  player.hop = 1
end

local function move_cars(dt)
  local mul = speed_mul()
  for i = 1, #lanes do
    local lane = lanes[i]
    local total = lane_total(lane)
    local dx = lane.dir * lane.speed * mul * dt
    local cars = lane.cars
    for c = 1, #cars do
      cars[c].x = wrap_mod(cars[c].x + dx, total)
    end
  end
end

local function player_center()
  local px = player.col * CW + CW // 2
  local py = HUD + player.row * RH + RH // 2
  return px, py
end

local function overlaps(px, x, w, py, cy)
  return px + HIT > x and px - HIT < x + w
     and py + HIT > cy and py - HIT < cy + CAR_H
end

local function colliding()
  local lane = lane_at[player.row]
  if not lane then return false end
  local px, py = player_center()
  local cy = HUD + player.row * RH + (RH - CAR_H) // 2
  local total = lane_total(lane)
  local cars = lane.cars
  for c = 1, #cars do
    local x = cars[c].x
    if overlaps(px, x, lane.w, py, cy) or overlaps(px, x - total, lane.w, py, cy) then
      return true
    end
  end
  return false
end

local function award()
  if player.row < progress then
    score = score + (progress - player.row) * 10
    progress = player.row
    score_flash = 0.35
  end
  if player.row == 0 then
    score = score + 100 + (round - 1) * 25
    clear_t = 0.85
    score_flash = 0.6
    badge.led.pulse(40, 255, 150, 420)
    badge.log("crossed")
  end
end

local function draw_dogecat(cx, cy, s, face)
  local function Y(oy)
    return math.floor(cy + oy * s)
  end
  local function box(ox, oy, w, h, color, rad)
    local x
    if face < 0 then
      x = cx - (ox + w) * s
    else
      x = cx + ox * s
    end
    g.fill_round_rect(math.floor(x), Y(oy), math.floor(w * s), math.floor(h * s), rad, color)
  end
  local function circ(ox, oy, r, color)
    g.fill_circle(math.floor(cx + ox * s * face), Y(oy), math.max(1, math.floor(r * s)), color)
  end
  local function tri(x1, y1, x2, y2, x3, y3, color)
    local function tx(x)
      return math.floor(cx + x * s * face)
    end
    g.fill_triangle(tx(x1), Y(y1), tx(x2), Y(y2), tx(x3), Y(y3), color)
  end
  local function dot(ox, oy, color)
    local x = math.floor(cx + ox * s * face)
    local y = Y(oy)
    if s <= 1 then
      g.pixel(x, y, color)
    else
      g.fill_rect(x, y, math.floor(s), math.floor(s), color)
    end
  end

  local rad = math.max(1, math.floor(2 * s))
  box(-5, 5, 10, 2, g.BLACK, 1)
  box(-7, 0, 11, 6, DOGE, rad)
  circ(4, 1, 3, DOGE)
  circ(6, 2, 2, DOGE_LT)
  tri(2, 0, 4, -4, 6, 0, DOGE_DK)
  dot(5, 1, g.BLACK)
  dot(7, 2, NOSE)
  circ(-2, -3, 3, CAT)
  -- Gameplay rows are 16px, so the ears stay inside the cell. The title
  -- scale can wear the taller pair.
  local tip = s > 1 and -8 or -6
  tri(-4, -4, -3, tip, -1, -4, CAT_LT)
  tri(-1, -4, 0, tip, 2, -4, CAT_LT)
  box(-4, -1, 4, 2, g.SOLANA_GREEN, 1)
  dot(-3, -3, g.WHITE)
  dot(-1, -3, g.WHITE)
end

local function draw_car(x, y, w, h, color, dir)
  x = math.floor(x)
  y = math.floor(y)
  if x >= W or x + w <= 0 then return end
  g.fill_round_rect(x, y, w, h, 2, color)
  local cab = math.max(6, w // 3)
  local cab_x = dir > 0 and (x + w - cab - 3) or (x + 3)
  g.fill_rect(cab_x, y + 2, cab, h - 5, WINDOW)
  local lamp_x = dir > 0 and (x + w - 3) or x + 1
  g.fill_rect(lamp_x, y + 2, 2, 2, LAMP)
  g.fill_rect(x + 3, y + h - 3, 4, 2, g.BLACK)
  g.fill_rect(x + w - 7, y + h - 3, 4, 2, g.BLACK)
end

local function draw_lane_cars(lane)
  local y = HUD + lane.row * RH + (RH - CAR_H) // 2
  local total = lane_total(lane)
  local cars = lane.cars
  for c = 1, #cars do
    local x = cars[c].x
    draw_car(x, y, lane.w, CAR_H, lane.color, lane.dir)
    draw_car(x - total, y, lane.w, CAR_H, lane.color, lane.dir)
  end
end

local function draw_rows()
  for row = 0, ROWS - 1 do
    local y = HUD + row * RH
    local lane = lane_at[row]
    if row == 0 then
      g.fill_rect(0, y, W // 2, RH, GOAL_L)
      g.fill_rect(W // 2, y, W - W // 2, RH, GOAL_R)
      g.text("GOAL", 6, y + 4, g.SOLANA_GREEN, 1)
    elseif row == 4 or row == 8 then
      g.fill_rect(0, y, W, RH, GRASS)
      for i = 0, 9 do
        local x = (i * 37 + row * 19) % (W - 4)
        g.fill_rect(x, y + 8, 2, 5, GRASS_DK)
        g.fill_rect(x, y + 5, 2, 3, TUFT)
      end
    elseif row >= 12 then
      g.fill_rect(0, y, W, RH, WALK)
      for x = 0, W - 1, 16 do
        if ((x // 16) + row) % 2 == 0 then
          g.fill_rect(x, y, 16, RH, WALK_LT)
        end
      end
      if row == START_ROW then
        g.fill_rect(0, y, W, 2, g.YELLOW)
      end
    else
      g.fill_rect(0, y, W, RH, ROAD)
      local off = 0
      if lane and lane.cars[1] then
        off = math.floor(lane.cars[1].x) % 20
      end
      local mid = y + RH // 2
      for x = -20, W, 20 do
        g.fill_rect(x + off, mid, 8, 1, DASH)
      end
    end
  end
end

local function draw_hud()
  for x = 0, W - 1, 2 do
    g.fill_rect(x, 0, 2, 2, g.gradient(x / W))
  end
  local sc = score_flash > 0 and g.SOLANA_GREEN or g.WHITE
  g.text("SCORE " .. score, 4, 5, sc, 1)
  g.text_center("R" .. round, W // 2, 5, g.SOLANA_GREEN, 1)
  g.text_right("BEST " .. best, W - 4, 5, g.MUTED, 1)
end

local function draw_player()
  local px, py = player_center()
  local bob = 0
  if player.hop > 0 then
    bob = -math.sin(player.hop * math.pi) * 2
  end
  draw_dogecat(px, py + bob, 1, player.face)
  if mode == "dead" then
    g.line(px - 6, py - 6, px + 6, py + 6, g.RED)
    g.line(px - 6, py + 6, px + 6, py - 6, g.RED)
  end
end

local function draw_banner()
  g.fill_round_rect(W // 2 - 78, H // 2 - 18, 156, 32, 4, g.BG)
  g.round_rect(W // 2 - 78, H // 2 - 18, 156, 32, 4, g.SOLANA_GREEN)
  g.text_center("NICE CROSS", W // 2, H // 2 - 10, g.SOLANA_GREEN, 2)
end

local function blink_on()
  return (t % 0.9) < 0.55
end

local function draw_dead()
  -- Tall enough to cover the sprite, so a splat on a low lane does not
  -- leave a sliver of the dogecat sticking out under the card.
  local x, y, w, h = 16, 28, 288, 196
  g.fill_round_rect(x, y, w, h, 6, g.PANEL)
  g.round_rect(x, y, w, h, 6, g.SOLANA_PURPLE)
  g.text_center("SPLAT", W // 2, y + 22, g.RED, 3)
  g.text_center("SCORE " .. score, W // 2, y + 56, g.WHITE, 2)
  g.text_center("BEST " .. best, W // 2, y + 78, g.SOLANA_GREEN, 2)
  if got_best then
    g.text_center("NEW BEST", W // 2, y + 102, g.SOLANA_GREEN, 1)
  end
  if blink_on() then
    g.text_center("PRESS " .. SELECT .. " TO RETRY", W // 2, y + 120, g.WHITE, 2)
  end
  g.text_center(CANCEL .. " TO TITLE", W // 2, y + 148, g.MUTED, 1)
end

local function draw_title()
  g.clear(g.BG)
  for x = 0, W - 1, 2 do
    g.fill_rect(x, 0, 2, 4, g.gradient(x / W))
  end
  g.text_right("BEST " .. best, W - 6, 8, g.MUTED, 1)
  g.text_center("DOGECAT", W // 2, 18, g.SOLANA_PURPLE, 5)
  g.text_center("CROSS", W // 2, 62, g.SOLANA_GREEN, 5)
  g.text_center("a dogecat.com game", W // 2, 110, g.MUTED, 1)

  local bob = math.floor(math.sin(t * 3) * 2)
  local ry = 156
  g.fill_rect(0, ry, W, 18, ROAD)
  g.fill_rect(0, ry + 8, W, 1, DASH)
  local cx = math.floor((t * 50) % (W + 70)) - 50
  draw_car(cx, ry + 4, 40, 10, g.SOLANA_PURPLE, 1)
  draw_dogecat(W // 2, 148 + bob, 3, 1)

  if blink_on() then
    g.text_center("PRESS " .. SELECT, W // 2, 186, g.WHITE, 2)
  end
  g.text_center("D-PAD MOVES   " .. CANCEL .. " QUITS", W // 2, 214, g.MUTED, 1)
end

local function draw_play()
  g.clear(g.BG)
  draw_rows()
  for i = 1, #lanes do
    draw_lane_cars(lanes[i])
  end
  draw_player()
  draw_hud()
  if clear_t > 0 then draw_banner() end
  if mode == "dead" then draw_dead() end
end

function on_start()
  SELECT = input.label("a") or "SELECT"
  CANCEL = input.label("b") or "CANCEL"
  badge.led.take()
  local saved = kv.get("best", "0")
  best = tonumber(saved) or 0
  if best < 0 then best = 0 end
  build_lanes()
  badge.log("dogecat cross")
end

function on_update(dt)
  if dt > 0.05 then dt = 0.05 end
  if dt < 0 then dt = 0 end
  t = t + dt
  if score_flash > 0 then
    score_flash = score_flash - dt
  end
  if player.hop > 0 then
    player.hop = player.hop - dt / 0.1
    if player.hop < 0 then player.hop = 0 end
  end

  if hold_key and not input.down(hold_key) then
    hold_key = nil
  end
  if mode == "play" and clear_t <= 0 and hold_key then
    hold_t = hold_t + dt
    if hold_t >= 0.16 and player.hop <= 0 then
      hold_t = 0
      try_hop(hold_key)
    end
  end

  if mode ~= "dead" then
    move_cars(dt)
  end

  if mode == "play" then
    if clear_t > 0 then
      clear_t = clear_t - dt
      if clear_t <= 0 then
        clear_t = 0
        round = round + 1
        spawn_player()
      end
    elseif colliding() then
      die()
    else
      award()
    end
  end

  if mode == "title" then
    local phase = (math.sin(t * 2) + 1) / 2
    badge.led.gradient(0, phase, 0.75)
    badge.led.gradient(1, 1 - phase, 0.75)
    badge.led.show()
  end
end

function on_draw()
  if mode == "title" then
    draw_title()
  else
    draw_play()
  end
end

function on_button(key, pressed)
  if not pressed then
    if key == hold_key then hold_key = nil end
    return
  end
  if key == "b" then
    hold_key = nil
    if mode == "dead" then
      mode = "title"
      badge.led.off()
      badge.log("title")
    else
      badge.system.exit()
    end
    return
  end
  if key == "a" then
    if mode == "title" or mode == "dead" then
      start_game()
    end
    return
  end
  if mode ~= "play" or clear_t > 0 then return end
  if key == "up" or key == "down" or key == "left" or key == "right" then
    try_hop(key)
    hold_key = key
    hold_t = 0
  end
end

function on_stop()
  commit_best()
  badge.led.off()
end
