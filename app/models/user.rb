class User < ApplicationRecord
  belongs_to :employee, optional: true

  ROLES = %w[admin user].freeze

  validates :login, presence: true, uniqueness: true
  validates :role, inclusion: { in: ROLES }
  validates :password_salt, :password_hash, presence: true

  before_validation :ensure_password_salt

  def admin?
    role == "admin"
  end

  def user?
    role == "user"
  end

  def password=(raw_password)
    self.password_salt = SecureRandom.hex(16)
    self.password_hash = self.class.password_hash_for(raw_password, password_salt)
  end

  def authenticate(raw_password)
    candidate = self.class.password_hash_for(raw_password, password_salt)
    ActiveSupport::SecurityUtils.secure_compare(candidate, password_hash) && self
  end

  def self.password_hash_for(raw_password, salt)
    OpenSSL::Digest::SHA256.hexdigest("#{salt}--#{raw_password}")
  end

  def self.ensure_login_for(employee)
    user = find_or_initialize_by(login: employee.employee_code)
    user.employee = employee
    user.password = employee.employee_code.downcase if user.new_record?
    user.save! if user.changed?
    user
  end

  private

  def ensure_password_salt
    self.password_salt ||= SecureRandom.hex(16)
  end
end
