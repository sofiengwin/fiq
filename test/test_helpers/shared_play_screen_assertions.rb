# frozen_string_literal: true

# Shared DOM contract assertions for the Q3 play screen shell
# (app/views/shared/_play_screen.html.erb). Both /play/question and
# saved quiz_attempt_path must satisfy every assertion here with the
# same selectors/ids.
module SharedPlayScreenAssertions
  def assert_shared_play_screen(body, question_number:, total_questions:, score:, streak:, effective_limit:, tile_count:, prompt_image_src: nil, form_action:, input_name:)
    doc = Nokogiri::HTML::Document.parse(body)

    header = doc.at_css("#play-header")
    assert header, "expected #play-header"

    progress = doc.at_css("#play-progress")
    assert progress, "expected #play-progress"
    assert_equal "Question #{question_number} of #{total_questions}", progress.text.strip

    score_el = doc.at_css("#play-score")
    assert score_el, "expected #play-score"
    assert_equal "Score: #{score}", score_el.text.strip

    streak_el = doc.at_css("#play-streak")
    if streak.to_i > 0
      assert streak_el, "expected #play-streak when streak > 0"
    else
      assert_nil streak_el, "expected no #play-streak when streak is 0"
    end

    countdown = doc.at_css("#play-countdown")
    assert countdown, "expected #play-countdown slot"
    assert_equal effective_limit.to_s, countdown.text.strip
    assert_equal "display", countdown["data-quiz-timer-target"]

    tiles = doc.at_css("#play-tiles")
    assert tiles, "expected #play-tiles"
    classes = tiles["class"].to_s.split
    assert_includes classes, "grid-cols-2", "tiles must be 2 columns at every width"
    assert_not_includes classes, "grid-cols-1"
    assert classes.none? { |c| c.include?("md:grid-cols") }, "tiles must not collapse to 1 column on small screens"
    assert_equal tile_count, doc.css("#play-tiles > label").size

    prompt = doc.at_css("#play-prompt")
    assert prompt, "expected #play-prompt"

    img = doc.at_css("#play-prompt-image")
    if prompt_image_src
      assert img, "expected #play-prompt-image when image_url is set"
      assert_equal prompt_image_src, img["src"]
      assert img.ancestors("a, button, label").empty?, "prompt image must never be a button/link"
      assert img.xpath("following::*[@id='play-prompt']").any?, "prompt image must render above the prompt text"
    else
      assert_nil img, "expected no #play-prompt-image when image_url is blank"
    end

    form = doc.at_css("form#play-form")
    assert form, "expected form#play-form"
    assert_equal form_action, form["action"]
    assert form.at_css("input[name='#{input_name}']"), "expected tile input named #{input_name}"
    assert form.at_css("#play-time-taken"), "expected #play-time-taken hidden field"
    # Q5 lock/confirm contract: Confirm (#play-submit) exists only in multi
    # mode (badge present); single-tap-lock mode renders no
    # submit/Confirm/Next control at all.
    if doc.at_css("#play-multi-badge")
      assert form.at_css("#play-submit"), "expected #play-submit Confirm in multi mode"
    else
      assert_nil form.at_css("#play-submit"), "expected no submit in single-tap-lock mode"
      assert_empty doc.css("#play-submit"), "expected no submit/Confirm anywhere in single mode"
    end
    assert_empty doc.css("a, button").select { |el| el.text.strip =~ /\ANext\b/i },
      "expected no Next button anywhere in the play loop"

    quit = doc.at_css("#play-quit")
    assert quit, "expected #play-quit under the tiles"
    quit_control = doc.at_css("#play-quit-control")
    assert quit_control, "expected #play-quit-control"
    assert_includes quit_control["class"].to_s.split, "text-sm", "quit must be a small control"
    assert quit_control.ancestors(".play-tile, #play-tiles").empty?, "quit must not be styled as an answer tile"
    assert doc.css("#play-quit .play-tile").empty?, "quit must not reuse answer tile styling"
  end
end
