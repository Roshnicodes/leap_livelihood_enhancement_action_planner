class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :employee, foreign_key: true
      t.string :login, null: false
      t.string :role, null: false, default: "user"
      t.string :password_salt, null: false
      t.string :password_hash, null: false

      t.timestamps
    end

    add_index :users, :login, unique: true
    add_index :users, :role
  end
end
