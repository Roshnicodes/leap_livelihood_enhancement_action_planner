module Api
  class ProjectSummaryApprovalsController < ApplicationController
    include ProjectSummaryReviewPresenter

    before_action :require_json_login
    before_action :require_summary_access_json
    before_action :require_summary_approver_json, only: %i[approve return_summary bulk_approve bulk_return]
    before_action :set_submission, only: %i[approve return_summary]

    STATUS_FILTERS = %w[pending forwarded approved returned].freeze

    def index
      ProjectSummarySubmissionItem.reset_column_information

      base_submissions = approval_scope
        .includes(:employee, :approver, :first_approver, :project_summary_submission_items)
        .order(submitted_at: :desc)
        .to_a
      vertical_options = vertical_options_for(base_submissions)
      selected_vertical = params[:vertical].to_s.presence_in(vertical_options)
      selected_status = params[:status].to_s.presence_in(STATUS_FILTERS)
      submissions = filter_api_submissions(base_submissions, selected_status, selected_vertical)
      summary_rows = summary_rows_for(submissions)
      summary_rows = filter_summary_rows_by_vertical(summary_rows, selected_vertical) if selected_vertical.present?

      render json: approval_payload(
        submissions: submissions,
        summary_rows: summary_rows,
        vertical_options: vertical_options,
        selected_vertical: selected_vertical,
        selected_status: selected_status
      )
    end

    def approve
      update_submission!("approved")
      render json: action_payload(@submission.reload)
    end

    def return_summary
      if params[:approval_remark].to_s.strip.blank?
        render json: { error: "Return remark is required." }, status: :unprocessable_entity
        return
      end

      update_submission!("returned")
      render json: action_payload(@submission.reload)
    end

    def bulk_approve
      submissions = update_submissions!("approved")
      render json: bulk_action_payload(submissions)
    end

    def bulk_return
      if params[:approval_remark].to_s.strip.blank?
        render json: { error: "Return remark is required." }, status: :unprocessable_entity
        return
      end

      submissions = update_submissions!("returned")
      render json: bulk_action_payload(submissions)
    end

    private

    def require_json_login
      return if current_user&.admin? || current_user&.employee&.active?

      reset_session if current_user
      render json: { error: "Please login to continue." }, status: :unauthorized
    end

    def require_summary_access_json
      return if current_user.admin? || summary_approver?

      render json: { error: "Approval access required." }, status: :forbidden
    end

    def require_summary_approver_json
      return if current_stage_approver?

      render json: { error: "Approval access required." }, status: :forbidden
    end

    def set_submission
      @submission = approval_scope
        .includes(:employee, :approver, :first_approver, :project_summary_submission_items)
        .find(params[:id])
    end

    def approval_scope
      if current_user.admin?
        ProjectSummarySubmission.all
      else
        ProjectSummarySubmission.where(approver: current_user.employee)
      end
    end

    def summary_approver?
      ProjectSummarySubmission.summary_approver?(current_user.employee)
    end

    def current_stage_approver?
      return false unless summary_approver?

      approval_scope.where(status: "pending", approver: current_user.employee).exists?
    end

    def filter_api_submissions(submissions, status_filter, vertical_filter)
      filtered = case status_filter
      when "pending"
        submissions.select { |submission| submission.pending? && submission.first_approver_id.blank? }
      when "forwarded"
        submissions.select { |submission| submission.pending? && submission.first_approver_id.present? }
      when "approved"
        submissions.select(&:approved?)
      when "returned"
        submissions.select(&:returned?)
      else
        submissions
      end

      vertical_filter.present? ? filter_submissions_by_vertical(filtered, vertical_filter) : filtered
    end

    def approval_payload(submissions:, summary_rows:, vertical_options:, selected_vertical:, selected_status:)
      {
        filters: {
          vertical: selected_vertical,
          status: selected_status
        },
        options: {
          verticals: vertical_options,
          statuses: STATUS_FILTERS
        },
        access: {
          can_approve: !current_user.admin? && summary_approver?,
          current_employee: employee_payload(current_user.employee)
        },
        summary: summary_payload(submissions, summary_rows),
        pending_approver_summaries: current_user.admin? ? pending_approver_summaries_payload(submissions) : [],
        project_record_groups: project_record_groups_payload(summary_rows),
        activity_summaries: activity_summaries_payload(summary_rows),
        submissions: submissions.map { |submission| submission_payload(submission) }
      }
    end

    def action_payload(submission)
      {
        message: action_message(submission),
        action: submission_action(submission),
        submission: submission_payload(submission)
      }
    end

    def bulk_action_payload(submissions)
      {
        message: "#{submissions.size} project summaries updated.",
        updated_count: submissions.size,
        submissions: submissions.map { |submission| submission_payload(submission.reload) }
      }
    end

    def summary_payload(submissions, summary_rows)
      {
        submission_count: submissions.size,
        pending_count: submissions.count { |submission| submission.pending? && submission.first_approver_id.blank? },
        forwarded_count: submissions.count { |submission| submission.pending? && submission.first_approver_id.present? },
        approved_count: submissions.count(&:approved?),
        returned_count: submissions.count(&:returned?),
        row_count: summary_rows.size,
        project_count: summary_rows.map { |row| row[:project_name] }.compact_blank.uniq.size,
        vertical_count: summary_rows.map { |row| row[:vertical_name].presence || "Unassigned Vertical" }.uniq.size,
        total_amount: decimal_value(summary_rows.sum { |row| row[:total_amount].to_d }),
        month_totals: decimal_hash(month_totals_for(summary_rows))
      }
    end

    def pending_approver_summaries_payload(submissions)
      submissions
        .select(&:pending?)
        .group_by { |submission| submission.approver || ProjectSummarySubmission.approver_employee }
        .map do |approver, approver_submissions|
          rows = approver_submissions.flat_map(&:project_summary_submission_items)
          {
            approver: employee_payload(approver),
            pending_count: approver_submissions.size,
            vertical_count: rows.map { |item| item.vertical_name.presence || "Unassigned Vertical" }.uniq.size,
            project_count: rows.map(&:project_name).compact_blank.uniq.size,
            total_amount: decimal_value(approver_submissions.sum { |submission| submission.total_amount.to_d })
          }
        end
        .sort_by { |summary| [ -summary[:pending_count], summary.dig(:approver, :name).to_s ] }
    end

    def project_record_groups_payload(summary_rows)
      project_record_groups_for(summary_rows).map do |project|
        {
          project_id: project_id_for(project[:project_name]),
          project_name: project[:project_name],
          employee_names: project[:employee_names],
          total_amount: decimal_value(project[:total_amount]),
          month_totals: decimal_hash(project[:month_totals]),
          rows: project[:rows].map { |row| summary_row_payload(row) }
        }
      end
    end

    def activity_summaries_payload(summary_rows)
      activity_summaries_for(summary_rows).map do |activity|
        {
          activity_name: activity[:activity_name],
          bli_code: activity[:bli_code],
          project_count: activity[:project_count],
          total_amount: decimal_value(activity[:total_amount]),
          month_totals: decimal_hash(activity[:month_totals]),
          month_changes: decimal_array_hash(activity[:month_changes]),
          projects: activity[:projects].map do |project|
            {
              project_id: project_id_for(project[:project_name]),
              project_name: project[:project_name],
              total_amount: decimal_value(project[:total_amount])
            }
          end
        }
      end
    end

    def submission_payload(submission)
      rows = submission.project_summary_submission_items.sort_by do |item|
        [ item.project_name.to_s, item.vertical_name.to_s, item.activity_name.to_s, item.id ]
      end
      {
        id: submission.id,
        status: submission.status,
        stage: submission_stage(submission),
        can_act: !current_user.admin? && submission.pending? && submission.approver_id == current_user.employee&.id,
        submitted_by: employee_payload(submission.employee),
        approver: employee_payload(submission.approver),
        first_approver: employee_payload(submission.first_approver),
        total_amount: decimal_value(submission.total_amount),
        submission_remark: submission.submission_remark,
        approval_remark: submission.approval_remark,
        submitted_at: datetime_value(submission.submitted_at),
        first_approved_at: datetime_value(submission.first_approved_at),
        reviewed_at: datetime_value(submission.reviewed_at),
        pb_applied_at: datetime_value(submission.pb_applied_at),
        projects: rows.map(&:project_name).compact_blank.uniq.sort,
        project_details: project_details_for(rows),
        verticals: rows.map { |item| item.vertical_name.presence || "Unassigned Vertical" }.uniq.sort,
        items: rows.map { |item| item_payload(item) }
      }
    end

    def item_payload(item)
      activity = source_activity_for(item.project_name, item.activity_name, item.vertical_name)
      month_amounts = VerticalPercent::MONTH_COLUMNS.index_with { |month| item.public_send(month).to_d }
      planned_amounts = planned_month_amounts_for(item.total_amount.to_d, item.vertical_name)
      month_deltas = month_deltas_for(month_amounts, planned_amounts)
      colored_source_data = colored_source_data_for(
        activity,
        project_name: item.project_name,
        activity_name: item.activity_name,
        vertical_name: item.vertical_name
      )

      {
        id: item.id,
        project_id: colored_source_data[:project_id],
        project_name: item.project_name,
        activity_name: item.activity_name,
        asa_activity_name: item.activity_name,
        vertical_name: item.vertical_name,
        bli_code: activity&.bli_code,
        project_bli_name: activity&.name,
        project_bli_code: activity&.bli_code,
        project_bli_allocated_fund: activity ? decimal_value(activity.allocated_fund) : nil,
        responsible_user_name: activity&.responsible_user_name,
        colored_source_data: colored_source_data,
        total_amount: decimal_value(item.total_amount),
        changed_total: decimal_value(item.changed_total),
        remark: item.remark,
        month_amounts: decimal_hash(month_amounts),
        planned_month_amounts: decimal_hash(planned_amounts),
        month_deltas: decimal_hash(month_deltas)
      }
    end

    def summary_row_payload(row)
      activity = source_activity_for(row[:project_name], row[:activity_name], row[:vertical_name])
      colored_source_data = colored_source_data_for(
        activity,
        project_name: row[:project_name],
        activity_name: row[:activity_name],
        vertical_name: row[:vertical_name]
      )

      {
        submission_id: row[:submission].id,
        project_id: colored_source_data[:project_id],
        project_name: row[:project_name],
        activity_name: row[:activity_name],
        asa_activity_name: row[:activity_name],
        vertical_name: row[:vertical_name],
        bli_code: activity&.bli_code || row[:bli_code],
        project_bli_name: activity&.name,
        project_bli_code: activity&.bli_code || row[:bli_code],
        project_bli_allocated_fund: activity ? decimal_value(activity.allocated_fund) : nil,
        responsible_user_name: activity&.responsible_user_name,
        colored_source_data: colored_source_data,
        employee_name: row[:employee_name],
        total_amount: decimal_value(row[:total_amount]),
        changed_total: decimal_value(row[:changed_total]),
        remark: row[:remark],
        month_amounts: decimal_hash(row[:month_amounts]),
        planned_month_amounts: decimal_hash(row[:planned_month_amounts]),
        month_deltas: decimal_hash(row[:month_deltas])
      }
    end

    def employee_payload(employee)
      return nil if employee.blank?

      {
        id: employee.id,
        employee_code: employee.employee_code,
        name: employee.name
      }
    end

    def project_details_for(rows)
      rows
        .map(&:project_name)
        .compact_blank
        .uniq
        .sort
        .map { |project_name| { project_id: project_id_for(project_name), project_name: project_name } }
    end

    def colored_source_data_for(activity, project_name:, activity_name:, vertical_name:)
      {
        project_id: project_id_for(project_name),
        project_bli_name: activity&.name,
        project_bli_code: activity&.bli_code,
        project_bli_allocated_fund: activity ? decimal_value(activity.allocated_fund) : nil,
        project_name: project_name,
        vertical_name: vertical_name,
        asa_activity_name: activity_name,
        responsible_user_name: activity&.responsible_user_name
      }
    end

    def source_activity_for(project_name, activity_name, vertical_name)
      source_activity_cache.fetch([ project_name.to_s, activity_name.to_s, vertical_name.to_s ]) do |key|
        source_activity_cache[key] = BliActivity.active.find_by(
          project_name: project_name,
          activity_name: activity_name,
          vertical_name: vertical_name
        )
      end
    end

    def source_activity_cache
      @source_activity_cache ||= {}
    end

    def project_id_for(project_name)
      normalized_name = project_name.to_s.squish
      return if normalized_name.blank?

      project_id_cache.fetch(normalized_name) do |key|
        project_id_cache[key] =
          ProjectInformationSheet
            .where("LOWER(project_title) = :project OR LOWER(project_id) = :project", project: key.downcase)
            .pick(:project_id) ||
          ActionPlanRow.active_import.where(project_name: key).where.not(project_id: [ nil, "" ]).pick(:project_id) ||
          ProjectOwnership.active.where(project_name: key).pick(:po_id)
      end
    end

    def project_id_cache
      @project_id_cache ||= {}
    end

    def update_submission!(status)
      ProjectSummarySubmission.transaction do
        @submission.update!(approval_attributes_for(@submission, status))
        @submission.apply_to_pb! if @submission.approved?
      end
    end

    def update_submissions!(status)
      submissions = approval_scope
        .includes(:employee, :approver, :first_approver, :project_summary_submission_items)
        .where(status: "pending", id: submission_ids)
      reviewed_at = Time.current
      updated = []

      ProjectSummarySubmission.transaction do
        submissions.find_each do |submission|
          submission.update!(approval_attributes_for(submission, status, reviewed_at))
          submission.apply_to_pb! if submission.approved?
          updated << submission
        end
      end

      updated
    end

    def approval_attributes_for(submission, status, reviewed_at = Time.current)
      return return_attributes(status, reviewed_at) if status == "returned"

      final_approver = ProjectSummarySubmission.final_approver_employee
      if submission.approver_id != final_approver&.id
        {
          status: "pending",
          approver: final_approver,
          first_approver: submission.first_approver || current_user&.employee || submission.approver,
          first_approved_at: reviewed_at,
          approval_remark: params[:approval_remark].to_s.strip,
          reviewed_at: nil
        }
      else
        {
          status: "approved",
          approval_remark: params[:approval_remark].to_s.strip,
          reviewed_at: reviewed_at
        }
      end
    end

    def return_attributes(status, reviewed_at)
      {
        status: status,
        approval_remark: params[:approval_remark].to_s.strip,
        reviewed_at: reviewed_at
      }
    end

    def submission_ids
      value = params[:submission_ids]
      return [] if value.blank?
      return value.split(",").map(&:squish).compact_blank if value.is_a?(String)

      Array(value).map(&:to_s).map(&:squish).compact_blank
    end

    def submission_stage(submission)
      return "approved" if submission.approved?
      return "returned" if submission.returned?
      return "final_approval" if submission.first_approver_id.present?

      "first_approval"
    end

    def action_message(submission)
      return "Project summary returned successfully." if submission.returned?
      return "Project summary approved successfully." if submission.approved?

      "Project summary forwarded successfully."
    end

    def submission_action(submission)
      return "returned" if submission.returned?
      return "approved" if submission.approved?

      "forwarded"
    end

    def decimal_hash(values)
      values.transform_values { |value| decimal_value(value) }
    end

    def decimal_array_hash(values)
      values.transform_values { |array| array.map { |value| decimal_value(value) } }
    end

    def decimal_value(value)
      format("%.2f", value.to_d)
    end

    def datetime_value(value)
      value&.iso8601
    end
  end
end
