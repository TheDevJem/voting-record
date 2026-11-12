class VotePosition < ApplicationRecord
  belongs_to :roll_call
  belongs_to :member
end
