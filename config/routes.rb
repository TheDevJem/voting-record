Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    get "representatives" => "representatives#index"
    get "address_suggestions" => "address_suggestions#index"
    resources :questions, only: %i[create show]
    resources :conversations, only: :show
    resources :members, only: %i[index show] do
      resource :summary, only: %i[show create]
      member do
        get :votes
        get :bills
      end
    end
  end
end
