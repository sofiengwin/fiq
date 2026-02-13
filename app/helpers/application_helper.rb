module ApplicationHelper
  # Kahoot-style colors for answer options
  def answer_color_class(color)
    case color
    when "red"    then "bg-kahoot-red"
    when "blue"   then "bg-kahoot-blue"
    when "green"  then "bg-kahoot-green"
    when "yellow" then "bg-kahoot-yellow"
    when "orange" then "bg-kahoot-orange"
    when "purple" then "bg-kahoot-purple"
    else "bg-gray-500"
    end
  end

  # Legacy method for backwards compatibility
  def answer_button_class(color)
    kahoot_answer_button_class(color)
  end

  # Kahoot-inspired large answer buttons
  def kahoot_answer_button_class(color)
    base = "w-full min-h-[100px] p-6 rounded-2xl font-bold text-white flex items-center transition-all duration-200"
    color_class = case color
    when "red"    then "bg-kahoot-red hover:bg-kahoot-red-light"
    when "blue"   then "bg-kahoot-blue hover:bg-kahoot-blue-light"
    when "green"  then "bg-kahoot-green hover:bg-kahoot-green-light"
    when "yellow" then "bg-kahoot-yellow hover:bg-kahoot-yellow-light"
    when "orange" then "bg-kahoot-orange hover:brightness-110"
    when "purple" then "bg-kahoot-purple hover:bg-kahoot-purple-light"
    else "bg-gray-500 hover:bg-gray-400"
    end
    "#{base} #{color_class}"
  end

  # Legacy method for backwards compatibility
  def answer_shape(color)
    kahoot_answer_shape(color)
  end

  # Kahoot-style shapes for each answer color
  def kahoot_answer_shape(color)
    case color
    when "red"    then "▲"  # Triangle
    when "blue"   then "◆"  # Diamond
    when "green"  then "●"  # Circle
    when "yellow" then "■"  # Square
    when "orange" then "★"  # Star
    when "purple" then "⬡"  # Hexagon
    else "○"
    end
  end

  # Kahoot background colors with opacity for form answer rows
  def kahoot_answer_bg_class(color)
    case color
    when "red"    then "bg-kahoot-red/80"
    when "blue"   then "bg-kahoot-blue/80"
    when "green"  then "bg-kahoot-green/80"
    when "yellow" then "bg-kahoot-yellow/80"
    when "orange" then "bg-kahoot-orange/80"
    when "purple" then "bg-kahoot-purple/80"
    else "bg-gray-500/80"
    end
  end
end
