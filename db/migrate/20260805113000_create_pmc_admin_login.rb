class CreatePmcAdminLogin < ActiveRecord::Migration[7.2]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    pmc = MigrationUser.find_or_initialize_by(login: "PMC")
    pmc.role = "admin"
    pmc.employee_id = nil if pmc.has_attribute?(:employee_id)
    assign_password(pmc, "pmc@123")
    pmc.save!

    MigrationUser.where(login: "admin@leap.local").where.not(id: pmc.id).delete_all
  end

  def down
    admin = MigrationUser.find_or_initialize_by(login: "admin@leap.local")
    admin.role = "admin"
    admin.employee_id = nil if admin.has_attribute?(:employee_id)
    assign_password(admin, "admin123")
    admin.save!
  end

  private

  def assign_password(user, raw_password)
    salt = SecureRandom.hex(16)
    user.password_salt = salt
    user.password_hash = OpenSSL::Digest::SHA256.hexdigest("#{salt}--#{raw_password}")
  end
end
