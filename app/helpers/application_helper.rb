module ApplicationHelper
  # Q4: locked Kahoot tile system — exactly 4 color/shape pairs, in order:
  # red-triangle, blue-diamond, yellow-circle, green-square.
  # Tiles render by position (index % 4), so >4 options repeat the cycle.
  TILE_PAIRS = [
    { color: "red", shape: "▲", sr: "red-triangle" },
    { color: "blue", shape: "◆", sr: "blue-diamond" },
    { color: "yellow", shape: "●", sr: "yellow-circle" },
    { color: "green", shape: "■", sr: "green-square" }
  ].freeze
  TILE_COLORS = TILE_PAIRS.map { |p| p[:color] }.freeze

  # Position-based tile color: tile at index i uses TILE_COLORS[i % 4].
  def tile_color_for(index)
    TILE_COLORS[index.to_i % TILE_COLORS.length]
  end

  # Map any stored color onto the 4 locked pairs. Question::COLORS keeps
  # its 6-color legacy values so old rows still validate; legacy-only
  # colors fold onto the cycle by legacy position (orange -> red,
  # purple -> blue). Unknown/nil -> nil (gray fallback in class helpers).
  def canonical_tile_color(color)
    name = color.to_s
    return name if TILE_COLORS.include?(name)
    if defined?(Question::COLORS) && Question::COLORS.include?(name)
      return TILE_COLORS[Question::COLORS.index(name) % TILE_COLORS.length]
    end
    nil
  end

  # Kahoot-style colors for answer options (locked to the 4 tile pairs).
  def answer_color_class(color)
    case canonical_tile_color(color)
    when "red"    then "bg-red-500"
    when "blue"   then "bg-blue-500"
    when "yellow" then "bg-yellow-500"
    when "green"  then "bg-green-500"
    else "bg-gray-500"
    end
  end

  def answer_button_class(color)
    base = "w-full p-6 rounded-xl font-bold text-white text-xl transition transform hover:scale-[1.02] focus:outline-none focus:ring-4"
    color_class = case canonical_tile_color(color)
    when "red"    then "bg-red-500 hover:bg-red-400 focus:ring-red-300"
    when "blue"   then "bg-blue-500 hover:bg-blue-400 focus:ring-blue-300"
    when "yellow" then "bg-yellow-500 hover:bg-yellow-400 focus:ring-yellow-300"
    when "green"  then "bg-green-500 hover:bg-green-400 focus:ring-green-300"
    else "bg-gray-500 hover:bg-gray-400 focus:ring-gray-300"
    end
    "#{base} #{color_class}"
  end

  def answer_shape(color)
    pair = TILE_PAIRS.find { |p| p[:color] == canonical_tile_color(color) }
    pair ? pair[:shape] : "○"
  end

  # Screen-reader label for a tile color (locked names double as the
  # non-color signal alongside shapes).
  def answer_sr_label(color)
    pair = TILE_PAIRS.find { |p| p[:color] == canonical_tile_color(color) }
    pair ? pair[:sr] : "answer"
  end

  # Score-based gradient for results display
  def score_gradient_class(percentage)
    case percentage
    when 80..100 then "from-green-500 to-green-700"
    when 60..79  then "from-blue-500 to-blue-700"
    when 40..59  then "from-yellow-500 to-yellow-700"
    else "from-red-500 to-red-700"
    end
  end

  # Q11 leaderboard time column: wall-clock duration (completed_at -
  # started_at, the locked tie-break) rendered as 45s / 1m 35s.
  def leaderboard_duration(attempt)
    seconds = attempt.duration_seconds
    return "—" if seconds.nil?

    total = seconds.round
    return "#{total}s" if total < 60

    "#{total / 60}m #{total % 60}s"
  end
end
