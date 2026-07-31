require "json"
require "fileutils"

namespace :leap do
  desc "Export complete LEAP database data. Usage: FILE=tmp/leap_snapshot.json bundle exec rails leap:export_snapshot"
  task export_snapshot: :environment do
    path = ENV.fetch("FILE", Rails.root.join("tmp/leap_snapshot.json").to_s)
    payload = {
      exported_at: Time.current.iso8601,
      tables: snapshot_models.to_h do |model|
        [
          model.table_name,
          model.order(model.primary_key).map { |record| record.attributes }
        ]
      end
    }

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(payload))

    puts "Exported LEAP snapshot to #{path}"
    payload[:tables].each { |table, rows| puts "#{table}: #{rows.size}" }
  end

  desc "Import complete LEAP database data, replacing current data. Usage: CONFIRM=replace FILE=tmp/leap_snapshot.json bundle exec rails leap:import_snapshot"
  task import_snapshot: :environment do
    unless ENV["CONFIRM"] == "replace"
      abort "Refusing to import without CONFIRM=replace"
    end

    path = ENV.fetch("FILE", Rails.root.join("tmp/leap_snapshot.json").to_s)
    payload = JSON.parse(File.read(path))
    tables = payload.fetch("tables")

    ActiveRecord::Base.transaction do
      snapshot_delete_models.each(&:delete_all)

      snapshot_models.each do |model|
        rows = tables.fetch(model.table_name, [])
        next if rows.blank?

        model.insert_all!(rows)
        reset_primary_key_sequence(model)
      end
    end

    puts "Imported LEAP snapshot from #{path}"
    snapshot_models.each { |model| puts "#{model.table_name}: #{model.count}" }
  end

  def snapshot_models
    [
      Employee,
      User,
      VerticalPercent,
      EmployeeVerticalMapping,
      BliActivity,
      PlanSubmission,
      PlanSubmissionItem,
      ProjectSummarySubmission,
      ProjectSummarySubmissionItem
    ]
  end

  def snapshot_delete_models
    [
      PlanSubmissionItem,
      PlanSubmission,
      ProjectSummarySubmissionItem,
      ProjectSummarySubmission,
      BliActivity,
      EmployeeVerticalMapping,
      VerticalPercent,
      User,
      Employee
    ]
  end

  def reset_primary_key_sequence(model)
    connection = ActiveRecord::Base.connection
    return unless connection.respond_to?(:reset_pk_sequence!)

    connection.reset_pk_sequence!(model.table_name)
  end
end
