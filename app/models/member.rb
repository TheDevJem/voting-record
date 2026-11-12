class Member < ApplicationRecord
  CHAMBERS = %w[house senate].freeze

  has_many :committee_memberships, dependent: :destroy
  has_many :committees, through: :committee_memberships
  has_many :bill_sponsorships, dependent: :destroy
  has_many :bills, through: :bill_sponsorships
  has_many :vote_positions, dependent: :destroy
  has_one :summary, class_name: "MemberSummary", dependent: :destroy

  validates :bioguide_id, presence: true, uniqueness: true
  validates :chamber, inclusion: { in: CHAMBERS }
end
