# frozen_string_literal: true

ROM::SQL.migration do
  change do
    create_table :tasks do
      primary_key :id
      column :title, String, null: false
      column :omni_id, String, null: false
      column :x, Float, null: true
      column :y, Float, null: true
    end
  end
end
