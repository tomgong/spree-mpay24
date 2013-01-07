Rails.application.routes.draw do
  resources :mpay_callbacks, :only => [:index]
  resource :mpay_confirmation, :controller => 'mpay_confirmation', :only => [:show]
  resource :mpay_error, :controller => 'mpay_error', :only => [:show]
end