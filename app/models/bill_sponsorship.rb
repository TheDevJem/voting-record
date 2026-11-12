class BillSponsorship < ApplicationRecord
  belongs_to :member
  belongs_to :bill
end
