-- geographic-location.lua
--
-- One geography note -> up to 4 cards:
--   Locate        -- "Where is X?" + map -> revealed map + facts
--   Identify      -- revealed map -> name + facts
--   FlagToCountry -- flag -> name + map
--   CountryToFlag -- name -> flag + map

local M = {}

function M.card_names()
  return { "Locate", "Identify", "FlagToCountry", "CountryToFlag" }
end

function M.generate(note, ctx)
  local result = {}

  local heading = note:heading(1)
  local name_text = heading and heading:text() or ""
  local name_html = heading and ("<h2>" .. heading:html() .. "</h2>") or ""

  -- Map: front_html hides the answer; back_html is a <style> that reveals
  -- it. Concatenating both gives a map with the answer layer visible.
  local map_block = note:code_block("map")
  local map_hidden = ""
  local map_visible = ""
  if map_block then
    local rendered = ctx:render("map", map_block:source())
    map_hidden = rendered.front_html
    map_visible = rendered.front_html .. rendered.back_html
  end

  local media_block = note:code_block("media")
  local flag_html = ""
  if media_block then
    flag_html = ctx:render("media", media_block:source()).front_html
  end

  local facts = ""
  if #note:sections() > 1 then
    facts = ctx:section_html(note, 2)
  end
  local hr = '<hr class="answer-divider">'

  -- Locate: question + blank map -> revealed map + facts
  local question = "<p>Where is <strong>" .. name_text .. "</strong>?</p>"
  result.LocateFront = question .. map_hidden
  result.LocateBack = question .. map_visible .. hr .. facts

  -- Identify: revealed map -> name + facts
  if map_hidden ~= "" then
    result.IdentifyFront = map_visible
    result.IdentifyBack = map_visible .. hr .. name_html .. facts
  end

  -- FlagToCountry: flag -> name + map
  if flag_html ~= "" then
    result.FlagToCountryFront = flag_html
    result.FlagToCountryBack = flag_html .. hr .. name_html .. map_visible
  end

  -- CountryToFlag: "What is the flag of X?" -> flag + map
  if flag_html ~= "" and name_html ~= "" then
    local flag_q = "<p>What is the flag of <strong>" .. name_text .. "</strong>?</p>"
    result.CountryToFlagFront = flag_q
    result.CountryToFlagBack = flag_q .. hr .. flag_html .. map_visible
  end

  return result
end

return M
