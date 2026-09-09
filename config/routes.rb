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
  get "report_masters" => "report_masters#index"
  get "report_information" => "report_information#index"
  resources :project_information_sheets, only: %i[index create]
  post "report_masters/pis_document_types" => "report_masters#create_pis_document_type", as: :pis_document_types_report_masters
  post "report_masters/donor_report_types" => "report_masters#create_donor_report_type", as: :donor_report_types_report_masters
  post "report_masters/fund_report_types" => "report_masters#create_fund_report_type", as: :fund_report_types_report_masters
  resources :pis_report_uploads, only: %i[index create] do
    post :document_types, on: :collection, action: :create_document_type
  end
  get "pis_report_records" => "pis_report_uploads#records"
  resources :donor_report_uploads, only: %i[index create] do
    post :report_types, on: :collection, action: :create_report_type
  end
  get "donor_report_records" => "donor_report_uploads#records"
  resources :fund_report_uploads, only: %i[index create] do
    post :report_types, on: :collection, action: :create_report_type
  end
  get "fund_report_records" => "fund_report_uploads#records"
  resources :action_plans, only: %i[index create] do
    get :download, on: :collection
  end
  resource :achievement_entry, only: %i[show update] do
    post :import_excel
    post :submit
  end
  get "achievement_entry_records" => "achievement_entry_records#index"
  get "achievement_approvals/:stage" => "achievement_approvals#index", as: :achievement_approvals
  patch "achievement_approvals/:stage/:id/approve" => "achievement_approvals#approve", as: :approve_achievement
  patch "achievement_approvals/:stage/:id/return" => "achievement_approvals#return_submission", as: :return_achievement
  resources :vertical_action_plans, only: %i[index create] do
    get :download, on: :collection
  end
  patch "vertical_action_plans" => "vertical_action_plans#update"
  get "action_plan_records" => "action_plan_records#index"
  post "action_plan_records" => "action_plan_records#create"
  get "action_plan_reports" => "action_plan_reports#index"
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

  namespace :api, defaults: { format: :json } do
    get "project_action_plan" => "action_plans#project"
    get "vertical_action_plan" => "action_plans#vertical"
    get "project_summary_approvals" => "project_summary_approvals#index"
    patch "project_summary_approvals/approve" => "project_summary_approvals#bulk_approve"
    patch "project_summary_approvals/return" => "project_summary_approvals#bulk_return"
    patch "project_summary_approvals/:id/approve" => "project_summary_approvals#approve"
    patch "project_summary_approvals/:id/return" => "project_summary_approvals#return_summary"
  end

  namespace :admin do
    resources :employees, only: %i[index create update] do
      patch :toggle_active, on: :member
    end
    get "action_plan_fco_mapping" => "action_plan_fco_mappings#index", as: :action_plan_fco_mapping
    post "action_plan_fco_mapping" => "action_plan_fco_mappings#create"
    patch "action_plan_fco_mapping" => "action_plan_fco_mappings#update"
    patch "action_plan_fco_mapping/:id" => "action_plan_fco_mappings#update_mapping", as: :update_action_plan_fco_mapping
    patch "action_plan_fco_mapping/:id/toggle_active" => "action_plan_fco_mappings#toggle_active", as: :toggle_action_plan_fco_mapping
    post "action_plan_fco_mapping/import" => "action_plan_fco_mappings#import", as: :import_action_plan_fco_mapping
    delete "action_plan_fco_mapping/:id" => "action_plan_fco_mappings#destroy", as: :destroy_action_plan_fco_mapping
    resources :pb_imports, only: %i[index create] do
      get :download, on: :collection
      get :download_file, on: :member
    end
    post "pb_imports/bli_activities" => "pb_imports#create_bli_activity", as: :pb_bli_activities
    patch "pb_imports/bli_activities/:id" => "pb_imports#update_bli_activity", as: :pb_bli_activity
    patch "pb_imports/bli_activities/:id/toggle_active" => "pb_imports#toggle_bli_activity", as: :toggle_pb_bli_activity
    post "pb_imports/parent_activity_assignments" => "pb_imports#create_parent_activity_assignment", as: :parent_activity_assignments
    patch "pb_imports/parent_activity_assignments/:id" => "pb_imports#update_parent_activity_assignment", as: :parent_activity_assignment
    patch "pb_imports/parent_activity_assignments/:id/toggle_active" => "pb_imports#toggle_parent_activity_assignment", as: :toggle_parent_activity_assignment
    resources :action_plan_imports, only: %i[index create] do
      get :download, on: :collection
      get :download_latest_files, on: :collection
      get :download_file, on: :member
    end
    post "action_plan_imports/action_plan_rows" => "action_plan_imports#create_action_plan_row", as: :action_plan_rows
    patch "action_plan_imports/action_plan_rows/:id" => "action_plan_imports#update_action_plan_row", as: :action_plan_row
    patch "action_plan_imports/action_plan_rows/:id/toggle_active" => "action_plan_imports#toggle_action_plan_row", as: :toggle_action_plan_row
    post "action_plan_imports/project_ownerships" => "action_plan_imports#create_project_ownership", as: :project_ownerships
    patch "action_plan_imports/project_ownerships/:id" => "action_plan_imports#update_project_ownership", as: :project_ownership
    patch "action_plan_imports/project_ownerships/:id/toggle_active" => "action_plan_imports#toggle_project_ownership", as: :toggle_project_ownership
    post "action_plan_imports/vertical_mappings" => "action_plan_imports#create_vertical_mapping", as: :action_plan_vertical_mappings
    patch "action_plan_imports/vertical_mappings/:id" => "action_plan_imports#update_vertical_mapping", as: :action_plan_vertical_mapping
    patch "action_plan_imports/vertical_mappings/:id/toggle_active" => "action_plan_imports#toggle_vertical_mapping", as: :toggle_action_plan_vertical_mapping
  end
end
