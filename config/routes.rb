Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    get "representatives" => "representatives#index"
    resources :members, only: %i[index show] do
      resource :summary, only: %i[show create]
      member do
        get :votes
        get :bills
      end
    end
  end
end
