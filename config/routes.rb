Site::Application.routes.draw do
  resources :contests do
    collection do
      get :current
    end
    member do
      get :start
      get :build
      get :propose
      get :grid
      get 'rounds/:round', action: 'show', as: 'round'
      get 'rounds/:round/match/:match_id', action: 'show', as: 'round_match'
      get 'rounds/:round/match/:match_id/users', action: 'users', as: 'round_match_users'
    end

    resources :contest_suggestions, path: 'suggestions', only: [:show, :create, :destroy]
    resources :contest_matches, path: 'matches' do
      member do
        post 'vote/:variant' => 'contest_matches#vote', as: 'vote'
      end
    end
  end
end
