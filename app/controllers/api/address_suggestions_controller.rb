module Api
  # GET /api/address_suggestions?q=<partial address or state>
  # Autocomplete for the "Find your representatives" box. See AddressSuggestions.
  class AddressSuggestionsController < ApplicationController
    def index
      render json: { suggestions: AddressSuggestions.new.call(params[:q]).map(&:to_h) }
    rescue AddressSuggestions::Unavailable => e
      Rails.logger.warn("AddressSuggestions unavailable: #{e.message}")
      render_error :service_unavailable, "suggestions_unavailable", "Address suggestions are unavailable right now."
    end
  end
end
