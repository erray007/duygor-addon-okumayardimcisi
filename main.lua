-- Reading Helper (example for stages 3 and 4 of the DuyGör plugin platform).
--
-- Events:   speech (the speech filter), app, notification, focus
-- Screen:   screen.ocr, screen.describe
--
-- The texts are written in English and translated with _() from the files in languages/
-- (tr.json for Turkish); setting labels and script descriptions are translated by DuyGör
-- itself. The list of built-in abbreviations follows the plugin's language (Turkish or
-- English; English for other languages). Script ids, setting names and file names stay as
-- they were, so gestures, saved settings and added abbreviations keep working after an
-- update.

local HISTORY_LIMIT = 50
local ABBREVIATION_FILE = "kisaltmalar.json"

-- "tr" for "tr", "pt" for "pt-BR".
local LANGUAGE = ((PLUGIN.language or ""):match("^%a+") or ""):lower()

settings.define({
  { name = "kisaltma", label = "Expand abbreviations (Dr. as Doctor)", type = "check", default = true },
  { name = "uygulamaAdi", label = "Say the app's name when the app changes", type = "check", default = false },
  { name = "bildirimKaydi", label = "Keep a notification history", type = "check", default = true },
  { name = "kimlik", label = "Say the view ID of the focused item (for plugin authors)",
    type = "check", default = false },
})

-- Settings are read from a file; the speech filter runs for every utterance, so they are
-- cached for 3 seconds.
local cachedSettings, cachedAt = nil, 0
local function setting(name)
  if not cachedSettings or os.time() - cachedAt >= 3 then
    cachedSettings, cachedAt = settings.all(), os.time()
  end
  return cachedSettings[name]
end

-- ------------------------------------------------------------------ abbreviations

local BUILT_IN = LANGUAGE == "tr" and {
  ["Hz."] = "Hazreti", ["Dr."] = "Doktor", ["Prof."] = "Profesör", ["Doç."] = "Doçent",
  ["Av."] = "Avukat", ["Sn."] = "Sayın", ["vb."] = "ve benzeri", ["vs."] = "vesaire",
  ["örn."] = "örneğin", ["bkz."] = "bakınız", ["Tel."] = "telefon", ["Cad."] = "Caddesi",
  ["Sok."] = "Sokak", ["Mah."] = "Mahallesi", ["Apt."] = "Apartmanı",
} or {
  ["Dr."] = "Doctor", ["Prof."] = "Professor", ["Mr."] = "Mister", ["Mrs."] = "Missus",
  ["Jr."] = "Junior", ["Sr."] = "Senior", ["e.g."] = "for example", ["i.e."] = "that is",
  ["etc."] = "et cetera", ["approx."] = "approximately", ["Ave."] = "Avenue",
  ["Dept."] = "Department", ["Tel."] = "telephone",
}

local function userAbbreviations()
  local text = file.read(ABBREVIATION_FILE)
  local ok, t = pcall(json.decode, text or "{}")
  return (ok and type(t) == "table") and t or {}
end

-- Pattern: an abbreviation must come after a space, the start of the text, or an opening
-- bracket or quote (so "ADr." is left alone). Patterns are built once and rebuilt when an
-- abbreviation is added.
local patterns
local function escape(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
local function buildPatterns()
  patterns = {}
  local all = {}
  for k, v in pairs(BUILT_IN) do all[k] = v end
  for k, v in pairs(userAbbreviations()) do all[k] = v end
  for k, v in pairs(all) do
    patterns[#patterns + 1] = { "([%s%(%[\"'])" .. escape(k), "%1" .. v:gsub("%%", "%%%%") }
  end
end

local function expand(text)
  if not patterns then buildPatterns() end
  local s, total = " " .. text, 0
  for i, p in ipairs(patterns) do
    local n
    s, n = s:gsub(p[1], p[2])
    total = total + n
  end
  if total == 0 then return nil end   -- unchanged: the screen reader speaks the original
  return s:sub(2)
end

-- ------------------------------------------------------------------ events

on("speech", function(text, package)
  if setting("kisaltma") then
    return expand(text)
  end
end)

on("app", function(newPackage, oldPackage)
  if setting("uygulamaAdi") then
    local name = app.label(newPackage)
    if name then speak(name) end
  end
end)

-- The notification history lives in memory; it is cleared when the plugin is reloaded.
HISTORY = {}

on("notification", function(package, text)
  if not setting("bildirimKaydi") or not text or text == "" then return end
  table.insert(HISTORY, 1, { time = os.date("%H:%M"), app = app.label(package) or package, text = text })
  while #HISTORY > HISTORY_LIMIT do table.remove(HISTORY) end
end)

on("focus", function(node)
  if setting("kimlik") and node.id then
    speak(node.id:gsub("^.-:id/", ""), false)
  end
end)

-- ------------------------------------------------------------------ scripts

script("sonBildirimler", "Recent notifications", function()
  if #HISTORY == 0 then
    speak(_("No notifications saved."))
    return
  end
  local lines = {}
  for i, n in ipairs(HISTORY) do
    lines[i] = n.time .. ", " .. n.app .. ": " .. n.text
  end
  window.text(_("Recent notifications"), table.concat(lines, "\n"))
end)

script("bildirimleriTemizle", "Clear the notification history", function()
  HISTORY = {}
  speak(_("Notification history cleared."))
end)

script("kisaltmaEkle", "Add an abbreviation", function()
  local short = window.input(_("Abbreviation"), "", _("For example Corp."))
  if not short or short:match("^%s*$") then return end
  local long = window.input(_("How should it be read?"), "", _("For example Corporation"))
  if not long or long:match("^%s*$") then return end
  local t = userAbbreviations()
  t[short] = long
  file.write(ABBREVIATION_FILE, json.encode(t, true))
  buildPatterns()
  speak(_("%s will now be read as %s.", short, long))
end)

script("kisaltmalar", "Show and delete abbreviations", function()
  local t = userAbbreviations()
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  local lines = {}
  for i, k in ipairs(keys) do lines[i] = k .. " → " .. t[k] end
  local builtIn = {}
  for k, v in pairs(BUILT_IN) do builtIn[#builtIn + 1] = k .. " → " .. v end
  table.sort(builtIn)
  lines[#lines + 1] = _("Show the built-in abbreviations")
  local chosen = window.list(_("My abbreviations"), lines)
  if not chosen then return end
  if chosen > #keys then
    window.text(_("Built-in abbreviations"), table.concat(builtIn, "\n"))
    return
  end
  local k = keys[chosen]
  if window.confirm(_("Delete abbreviation"), _("Delete %s?", k)) then
    t[k] = nil
    file.write(ABBREVIATION_FILE, json.encode(next(t) and t or {}, true))
    buildPatterns()
    speak(_("%s deleted.", k))
  end
end)

local function showOcr(title, source)
  speak(_("Recognizing"))
  local text, err = screen.ocr(source)
  if not text then
    playSound("error")
    speak(_("Could not recognize text.") .. " " .. (err or ""))
    return
  end
  if text == "" then
    speak(_("No text found."))
    return
  end
  window.text(title, text)
end

script("ekranYazisi", "Recognize the text on the screen", function()
  showOcr(_("Text on the screen"), nil)
end)

script("odakYazisi", "Recognize the text of the focused item", function()
  local node = focus()
  if not node then
    speak(_("Nothing is focused."))
    return
  end
  showOcr(_("Text in the item"), node)
end)

script("ekranaSor", "Ask a question about the screen", function()
  -- Take the picture before the question window opens, so the window is not in it.
  local image = screen.screenshot()
  if not image then
    speak(_("Could not take a screenshot."))
    return
  end
  local question = window.input(_("What would you like to ask about the screen?"),
                                "", _("Leave empty to describe the screen"))
  if question == nil then return end
  speak(_("Asking the AI, please wait."))
  local answer, err = screen.describe(question, image)
  if not answer then
    playSound("error")
    speak(_("No answer.") .. " " .. (err or ""))
    return
  end
  window.text(_("The AI's answer"), answer)
end)

script("ayarlar", "Reading Helper settings", function()
  if settings.open() then
    cachedSettings = nil
    speak(_("Settings saved."))
  end
end)
