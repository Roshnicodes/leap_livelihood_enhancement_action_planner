module ActionPlanSubmitting
  extend ActiveSupport::Concern

  private

  def existing_submission_for(project_name, plan_type: "project")
    return if project_name.blank? || current_user.employee.blank?

    current_user.employee.action_plan_submissions
      .where(project_name: project_name, plan_type: plan_type)
      .order(submitted_at: :desc)
      .first
  end

  def unbalanced_rows_message(rows)
    count = rows.unbalanced.count
    return if count.zero?

    "#{count} #{"activity".pluralize(count)} #{count == 1 ? "does" : "do"} not match the planned total. " \
      "Adjust the monthly targets so every row matches its total before submitting."
  end

  def submit_action_plan(project_name:, rows:, redirect_path:, plan_type: "project")
    if current_user.employee.blank?
      redirect_to redirect_path, alert: "Only employee accounts can submit an action plan."
      return
    end

    po_id = rows.first&.po_id
    if po_id.blank?
      redirect_to redirect_path, alert: "Please choose a valid project."
      return
    end

    imbalance = unbalanced_rows_message(rows)
    if imbalance.present?
      redirect_to redirect_path, alert: imbalance
      return
    end

    submission = build_action_plan_submission(project_name: project_name, po_id: po_id, plan_type: plan_type)

    if submission.save
      redirect_to redirect_path, notice: "#{submission.plan_type_label} sent for Project Owner approval."
    else
      redirect_to redirect_path, alert: submission.errors.full_messages.to_sentence
    end
  end

  def build_action_plan_submission(project_name:, po_id:, plan_type:)
    submission = current_user.employee.action_plan_submissions
      .where.not(status: "approved")
      .where(project_name: project_name, plan_type: plan_type)
      .order(submitted_at: :desc)
      .first_or_initialize

    submission.assign_attributes(
      project_ownership: resolve_project_ownership(project_name, po_id),
      plan_type: plan_type,
      po_id: po_id,
      project_name: project_name,
      submission_remark: params[:submission_remark].to_s.strip,
      status: "pending",
      current_stage: "po",
      submitted_at: Time.current,
      po_reviewed_at: nil,
      coo_reviewed_at: nil,
      director_reviewed_at: nil,
      po_remark: nil,
      coo_remark: nil,
      director_remark: nil
    )

    submission
  end

  def resolve_project_ownership(project_name, po_id)
    project_ownership_for(project_name) ||
      ProjectOwnership.find_by(po_id: po_id, project_name: project_name) ||
      ProjectOwnership.find_by(po_id: po_id) ||
      ProjectOwnership.find_by(project_name: project_name)
  end
end
