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
  get "budget_utilizations" => "budget_utilizations#index", as: :budget_utilizations
  patch "budget_utilizations" => "budget_utilizations#update"
  get "budget_utilization_reports" => "budget_utilization_reports#index", as: :budget_utilization_reports
  resources :pis_report_uploads, only: %i[index create] do
    post :document_types, on: :collection, action: :create_document_type
  end
  resources :donor_report_uploads, only: %i[index create] do
    post :report_types, on: :collection, action: :create_report_type
  end
  resources :fund_report_uploads, only: %i[index create] do
    post :report_types, on: :collection, action: :create_report_type
  end
  resources :action_plans, only: %i[index create]
  resource :achievement_entry, only: %i[show update] do
    post :submit
  end
  get "achievement_approvals/:stage" => "achievement_approvals#index", as: :achievement_approvals
  patch "achievement_approvals/:stage/:id/approve" => "achievement_approvals#approve", as: :approve_achievement
  patch "achievement_approvals/:stage/:id/return" => "achievement_approvals#return_submission", as: :return_achievement
  resources :vertical_action_plans, only: %i[index create]
  patch "vertical_action_plans" => "vertical_action_plans#update"
  get "action_plan_records" => "action_plan_records#index"
  post "action_plan_records" => "action_plan_records#create"
  get "action_plan_approvals/:stage" => "action_plan_approvals#index", as: :action_plan_approvals
  patch "action_plan_approvals/:stage/:id/approve" => "action_plan_approvals#approve", as: :approve_action_plan
  patch "action_plan_approvals/:stage/:id/return" => "action_plan_approvals#return_plan", as: :return_action_plan
  get "project_summary" => "project_summaries#index"
  post "project_summary" => "project_summaries#create"
  get "project_summary_records" => "project_summary_records#index"
  patch "project_summary_records" => "project_summary_records#bulk_update", as: :bulk_project_summary_records
  patch "project_summary_records/:id" => "project_summary_records#update", as: :project_summary_record
  get "project_summary_approvals" => "project_summary_approvals#index"
  get "project_summary_approval_records" => "project_summary_approval_records#index"
  patch "project_summary_approvals/approve" => "project_summary_approvals#bulk_approve", as: :bulk_approve_project_summaries
  patch "project_summary_approvals/return" => "project_summary_approvals#bulk_return", as: :bulk_return_project_summaries
  patch "project_summary_approvals/:id/approve" => "project_summary_approvals#approve", as: :approve_project_summary
  patch "project_summary_approvals/:id/return" => "project_summary_approvals#return_summary", as: :return_project_summary

  namespace :admin do
    resources :employees, only: :index
    resources :pb_imports, only: %i[index create] do
      get :download, on: :collection
      get :download_file, on: :member
    end
    resources :action_plan_imports, only: %i[index create] do
      get :download, on: :collection
      get :download_file, on: :member
    end
  end
end
