# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "Seeding database..."

# Sample Quiz 1: General Knowledge
quiz1 = Quiz.find_or_create_by!(title: "General Knowledge Trivia") do |q|
  q.description = "Test your knowledge with these fun trivia questions!"
  q.time_limit_seconds = 20
  q.scoring_mode = "partial_credit"
end

if quiz1.questions.empty?
  # Question 1
  q1 = quiz1.questions.create!(
    text: "What is the capital of France?",
    points: 1000,
    order_index: 0
  )
  q1.answer_options.create!([
    { text: "Paris", is_correct: true, color: "red", order_index: 0 },
    { text: "London", is_correct: false, color: "blue", order_index: 1 },
    { text: "Berlin", is_correct: false, color: "green", order_index: 2 },
    { text: "Madrid", is_correct: false, color: "yellow", order_index: 3 }
  ])

  # Question 2
  q2 = quiz1.questions.create!(
    text: "Which planet is known as the Red Planet?",
    points: 1000,
    order_index: 1
  )
  q2.answer_options.create!([
    { text: "Venus", is_correct: false, color: "red", order_index: 0 },
    { text: "Mars", is_correct: true, color: "blue", order_index: 1 },
    { text: "Jupiter", is_correct: false, color: "green", order_index: 2 },
    { text: "Saturn", is_correct: false, color: "yellow", order_index: 3 }
  ])

  # Question 3
  q3 = quiz1.questions.create!(
    text: "What is the largest mammal on Earth?",
    points: 1000,
    order_index: 2
  )
  q3.answer_options.create!([
    { text: "Elephant", is_correct: false, color: "red", order_index: 0 },
    { text: "Blue Whale", is_correct: true, color: "blue", order_index: 1 },
    { text: "Giraffe", is_correct: false, color: "green", order_index: 2 },
    { text: "Polar Bear", is_correct: false, color: "yellow", order_index: 3 }
  ])
end

# Sample Quiz 2: Programming
quiz2 = Quiz.find_or_create_by!(title: "Programming Basics") do |q|
  q.description = "How well do you know programming concepts?"
  q.time_limit_seconds = 30
  q.scoring_mode = "all_or_nothing"
end

if quiz2.questions.empty?
  # Question 1
  q1 = quiz2.questions.create!(
    text: "Which of these are programming languages? (Select all that apply)",
    points: 1500,
    order_index: 0
  )
  q1.answer_options.create!([
    { text: "Python", is_correct: true, color: "red", order_index: 0 },
    { text: "HTML", is_correct: false, color: "blue", order_index: 1 },
    { text: "Ruby", is_correct: true, color: "green", order_index: 2 },
    { text: "CSS", is_correct: false, color: "yellow", order_index: 3 }
  ])

  # Question 2
  q2 = quiz2.questions.create!(
    text: "What does 'API' stand for?",
    points: 1000,
    order_index: 1
  )
  q2.answer_options.create!([
    { text: "Application Programming Interface", is_correct: true, color: "red", order_index: 0 },
    { text: "Applied Programming Integration", is_correct: false, color: "blue", order_index: 1 },
    { text: "Application Process Integration", is_correct: false, color: "green", order_index: 2 },
    { text: "Automated Programming Interface", is_correct: false, color: "yellow", order_index: 3 }
  ])

  # Question 3
  q3 = quiz2.questions.create!(
    text: "Which company created Ruby on Rails?",
    points: 1000,
    order_index: 2
  )
  q3.answer_options.create!([
    { text: "Google", is_correct: false, color: "red", order_index: 0 },
    { text: "Basecamp (37signals)", is_correct: true, color: "blue", order_index: 1 },
    { text: "Microsoft", is_correct: false, color: "green", order_index: 2 },
    { text: "Facebook", is_correct: false, color: "yellow", order_index: 3 }
  ])
end

puts "Created #{Quiz.count} quizzes with #{Question.count} questions and #{AnswerOption.count} answer options."
