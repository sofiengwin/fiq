# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    @recent_quizzes = Quiz.order(created_at: :desc).limit(6)
  end
end
