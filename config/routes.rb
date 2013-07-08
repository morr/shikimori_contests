Site::Application.routes.draw do
  resources :contests do
    collection do
      get :current
    end
    member do
      get :start
      #get :finish
      get :build
      get :grid
      get 'rounds/:round', action: 'show', as: 'round'
      get 'rounds/:round/vote/:vote_id', action: 'show', as: 'round_vote'
      get 'rounds/:round/vote/:vote_id/users', action: 'users', as: 'round_vote_users'
    end

    resources :contest_votes, path: 'votes' do
      member do
        post 'vote/:variant' => 'contest_votes#vote', as: 'vote'
      end
    end
  end
end
