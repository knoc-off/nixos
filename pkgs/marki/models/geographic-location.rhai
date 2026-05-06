// geographic-location.rhai
//
// One geography note → up to 4 cards:
//   Locate       — "Where is X?" + map → revealed map + facts
//   Identify     — revealed map → name + facts
//   FlagToCountry — flag → name + map
//   CountryToFlag — name → flag + map

fn card_names() {
    ["Locate", "Identify", "FlagToCountry", "CountryToFlag"]
}

fn generate(note, ctx) {
    let result = #{};

    let heading = note.heading(0);
    let name_text = if heading != () { heading.text } else { "" };
    let name_html = if heading != () { `<h2>${heading.html}</h2>` } else { "" };

    // Map: front_html has answer hidden, back_html is a <style> that reveals it.
    // Concatenating both gives a map with the answer layer visible.
    let map_block = note.code_block("map");
    let map_hidden = "";
    let map_visible = "";
    if map_block != () {
        let rendered = ctx.render("map", map_block.source);
        map_hidden = rendered.front_html;
        map_visible = rendered.front_html + rendered.back_html;
    }

    let media_block = note.code_block("media");
    let flag_html = "";
    if media_block != () {
        flag_html = ctx.render("media", media_block.source).front_html;
    }

    let facts = if note.sections().len() > 1 { note.section_html(1) } else { "" };
    let hr = `<hr class="answer-divider">`;

    // Locate: question + blank map → revealed map + facts
    let question = `<p>Where is <strong>${name_text}</strong>?</p>`;
    result.LocateFront = question + map_hidden;
    result.LocateBack = question + map_visible + hr + facts;

    // Identify: revealed map → name + facts
    if map_hidden != "" {
        result.IdentifyFront = map_visible;
        result.IdentifyBack = map_visible + hr + name_html + facts;
    }

    // FlagToCountry: flag → name + map
    if flag_html != "" {
        result.FlagToCountryFront = flag_html;
        result.FlagToCountryBack = flag_html + hr + name_html + map_visible;
    }

    // CountryToFlag: "What is the flag of X?" → flag + map
    if flag_html != "" && name_html != "" {
        let flag_q = `<p>What is the flag of <strong>${name_text}</strong>?</p>`;
        result.CountryToFlagFront = flag_q;
        result.CountryToFlagBack = flag_q + hr + flag_html + map_visible;
    }

    result
}
