class CommitteeMembership < ApplicationRecord
  belongs_to :member
  belongs_to :committee
end
