module Api
  # GET /api/representatives?q=<state name, state code, or street address>
  # Returns a person's two senators and their House member (or every House member, for a state search).
  class RepresentativesController < ApplicationController
    def index
      query = params[:q].to_s.squish
      return render_error(:bad_request, "missing_query", "Enter a street address or a state.") if query.blank?

      if (state_code = state_code_for(query))
        render json: payload(match_type: "state", state_code:, house: house_members(state_code))
      else
        address_lookup(query)
      end
    end

    private

    def address_lookup(query)
      result = DistrictLookup.new.call(query)
      if result.state_code.blank? || Member.where(state_code: result.state_code).none?
        return render_error :not_found, "no_members", "We found that address, but have no members on file for that location."
      end

      house = house_members(result.state_code).where(district: result.district) # empty if the seat is vacant
      render json: payload(match_type: "address", state_code: result.state_code, house:,
                           matched_address: result.matched_address, district: result.district)
    rescue DistrictLookup::NotFound
      render_error :not_found, "address_not_found",
                   "We couldn't match that address. Try a full street address with city and state (e.g. 100 State St, Montpelier, VT), or just a state name."
    rescue DistrictLookup::Unavailable => e
      Rails.logger.warn("DistrictLookup unavailable: #{e.message}")
      render_error :service_unavailable, "lookup_unavailable",
                   "Address lookup is temporarily unavailable. You can still search by state name."
    end

    # Matches "VT", "vt", "Vermont", "vermont"
    def state_code_for(query)
      states = Member.distinct.pluck(:state, :state_code)
      states.find { |name, code| query.casecmp?(code) || query.casecmp?(name) }&.last
    end

    def house_members(state_code)
      Member.where(chamber: "house", state_code:).order(:district, :last_name)
    end

    def payload(match_type:, state_code:, house:, matched_address: nil, district: nil)
      senators = Member.where(chamber: "senate", state_code:).order(:last_name)
      {
        match_type:, matched_address:, district:, state_code:,
        state: senators.first&.state || house.first&.state,
        senators: senators.map { |m| summary(m) },
        house: house.map { |m| summary(m) }
      }
    end

    def summary(m)
      m.slice(:bioguide_id, :chamber, :full_name, :party, :state, :state_code, :district, :image_url, :phone, :website_url)
    end
  end
end
