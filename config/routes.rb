Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "sessions#new"

  get "login" => "sessions#new"
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy"

  get "dashboard" => "dashboard#index"
  resources :plan_submissions, only: %i[index create]
  get "project_summary" => "project_summaries#index"
  post "project_summary" => "project_summaries#create"
  get "project_summary_records" => "project_summary_records#index"
  patch "project_summary_records" => "project_summary_records#bulk_update", as: :bulk_project_summary_records
  patch "project_summary_records/:id" => "project_summary_records#update", as: :project_summary_record
  get "project_summary_approvals" => "project_summary_approvals#index"
  patch "project_summary_approvals/approve" => "project_summary_approvals#bulk_approve", as: :bulk_approve_project_summaries
  patch "project_summary_approvals/return" => "project_summary_approvals#bulk_return", as: :bulk_return_project_summaries
  patch "project_summary_approvals/:id/approve" => "project_summary_approvals#approve", as: :approve_project_summary
  patch "project_summary_approvals/:id/return" => "project_summary_approvals#return_summary", as: :return_project_summary

  namespace :admin do
    resources :employees, only: :index
  end
end
