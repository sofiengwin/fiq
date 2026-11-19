# frozen_string_literal: true

require "test_helper"

# Q4: locked Kahoot tile system — exactly 4 color/shape pairs in order,
# position-based cycling, legacy color reconciliation, SR labels.
class ApplicationHelperTilesTest < ActionView::TestCase
  tests ApplicationHelper
  test "tile pairs are exactly 4 in locked order red/blue/yellow/green" do
    assert_equal %w[red blue yellow green], ApplicationHelper::TILE_COLORS
    assert_equal 4, ApplicationHelper::TILE_PAIRS.length
  end

  test "answer shapes map red-triangle blue-diamond yellow-circle green-square" do
    assert_equal "▲", answer_shape("red")
    assert_equal "◆", answer_shape("blue")
    assert_equal "●", answer_shape("yellow")
    assert_equal "■", answer_shape("green")
  end

  test "answer sr labels match locked names" do
    assert_equal "red-triangle", answer_sr_label("red")
    assert_equal "blue-diamond", answer_sr_label("blue")
    assert_equal "yellow-circle", answer_sr_label("yellow")
    assert_equal "green-square", answer_sr_label("green")
  end

  test "tile_color_for wraps index % 4 past four options" do
    assert_equal %w[red blue yellow green red blue],
      (0..5).map { |i| tile_color_for(i) }
  end

  test "legacy Question::COLORS constant keeps 6 colors for old data" do
    assert_equal %w[red blue green yellow orange purple], Question::COLORS
  end

  test "legacy-only stored colors fold onto the 4 locked pairs" do
    assert_equal "red", canonical_tile_color("orange")
    assert_equal "blue", canonical_tile_color("purple")
    assert_equal "green", canonical_tile_color("green")
    assert_equal "yellow", canonical_tile_color("yellow")
    assert_nil canonical_tile_color("chartreuse")
    assert_nil canonical_tile_color(nil)
  end

  test "button and color classes cover only the 4 pairs plus gray fallback" do
    assert_match(/bg-red-500/, answer_button_class("red"))
    assert_match(/bg-blue-500/, answer_button_class("blue"))
    assert_match(/bg-yellow-500/, answer_button_class("yellow"))
    assert_match(/bg-green-500/, answer_button_class("green"))
    assert_match(/bg-gray-500/, answer_button_class("chartreuse"))
    assert_equal "bg-gray-500", answer_color_class("not-a-color")
  end

  test "tile CSS caps lock transition at 200ms" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    tile_rule = css[/\.play-tile\s*\{[^}]*\}/m]
    assert tile_rule, "expected a .play-tile rule (test hook)"
    duration = tile_rule[/transition-duration:\s*([\d.]+)ms/, 1]
    assert duration, "expected explicit transition-duration on .play-tile"
    assert_operator duration.to_f, :<=, 200, "lock/color change must be <=200ms"
  end

  test "tile CSS honors prefers-reduced-motion without dropping final colors" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    media = css[/@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{(.*)\}\s*\z/m, 1]
    assert media, "expected @media (prefers-reduced-motion: reduce) block"
    assert_match(/transform:\s*none/, media, "reduced motion must disable transforms")
    assert_match(/scale:\s*none/, media, "reduced motion must disable tile scaling")
    assert_match(/animation:\s*none/, media, "reduced motion must disable pulse/animation")
    assert_match(/\.play-tile\.is-correct\s*\{[^}]*background-color/m, css,
      "correct tile highlight must still be defined for reduced motion")
    refute_match(/\.play-tile\.is-correct\s*\{[^}]*background[^}]*:(\s*transparent|none)/, css)
  end

  test "no audio or beep in play javascript" do
    Dir[Rails.root.join("app/javascript/**/*.js")].each do |file|
      src = File.read(file)
      assert_no_match(/new\s+Audio|AudioContext|Oscillator|\.beep\(|<audio/i, src,
        "#{file} must not play sound (Q4: tiles are visual-only)")
    end
  end
end
