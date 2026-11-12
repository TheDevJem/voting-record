class Committee < ApplicationRecord
  belongs_to :parent, class_name: "Committee", optional: true
  has_many :subcommittees, class_name: "Committee", foreign_key: :parent_id, dependent: :destroy
  has_many :committee_memberships, dependent: :destroy
end
