class ApplicationController < ActionController::API
  # Every API failure comes back as JSON: { error: { code:, message: } } with a meaningful status.
  rescue_from StandardError, with: :render_internal_error
  rescue_from ActiveRecord::ConnectionNotEstablished, ActiveRecord::DatabaseConnectionError,
              ActiveRecord::NoDatabaseError, PG::ConnectionBad, with: :render_database_unavailable
  rescue_from ActiveRecord::StatementInvalid, with: :render_database_error
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  private

  def render_error(status, code, message)
    render json: { error: { code:, message: } }, status:
  end

  def render_not_found(_error)
    render_error :not_found, "not_found", "We couldn't find that record. It may have been removed in the latest sync."
  end

  def render_bad_request(error)
    render_error :bad_request, "bad_request", error.message
  end

  def render_database_unavailable(error)
    log_error(error)
    render_error :service_unavailable, "database_unavailable", "The database is unavailable right now. Please try again shortly."
  end

  def render_database_error(error)
    log_error(error)
    # Most likely cause in development: migrations haven't been run.
    render_error :service_unavailable, "database_error", "The data store isn't ready. Try running bin/rails db:prepare and congress:sync."
  end

  def render_internal_error(error)
    raise error if Rails.env.test? # surface real bugs in tests
    log_error(error)
    render_error :internal_server_error, "internal_error", "Something went wrong on our end. Please try again."
  end

  def log_error(error)
    Rails.logger.error("#{error.class}: #{error.message}\n#{Array(error.backtrace).first(10).join("\n")}")
  end
end
