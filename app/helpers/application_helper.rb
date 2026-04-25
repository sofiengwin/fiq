module ApplicationHelper
  # Kahoot-style colors for answer options
  def answer_color_class(color)
    case color
    when "red"    then "bg-red-500"
    when "blue"   then "bg-blue-500"
    when "green"  then "bg-green-500"
    when "yellow" then "bg-yellow-500"
    when "orange" then "bg-orange-500"
    when "purple" then "bg-purple-500"
    else "bg-gray-500"
    end
  end

  def answer_button_class(color)
    base = "w-full p-6 rounded-xl font-bold text-white text-xl transition transform hover:scale-[1.02] focus:outline-none focus:ring-4"
    color_class = case color
    when "red"    then "bg-red-500 hover:bg-red-400 focus:ring-red-300"
    when "blue"   then "bg-blue-500 hover:bg-blue-400 focus:ring-blue-300"
    when "green"  then "bg-green-500 hover:bg-green-400 focus:ring-green-300"
    when "yellow" then "bg-yellow-500 hover:bg-yellow-400 focus:ring-yellow-300"
    when "orange" then "bg-orange-500 hover:bg-orange-400 focus:ring-orange-300"
    when "purple" then "bg-purple-500 hover:bg-purple-400 focus:ring-purple-300"
    else "bg-gray-500 hover:bg-gray-400 focus:ring-gray-300"
    end
    "#{base} #{color_class}"
  end

  def answer_shape(color)
    case color
    when "red"    then "▲"
    when "blue"   then "◆"
    when "green"  then "●"
    when "yellow" then "■"
    when "orange" then "★"
    when "purple" then "⬡"
    else "○"
    end
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
end
