class ResponseAnswer < ApplicationRecord
  belongs_to :response
  belongs_to :answer_option
end
