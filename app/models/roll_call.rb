class RollCall < ApplicationRecord
  has_many :vote_positions, dependent: :destroy
end
