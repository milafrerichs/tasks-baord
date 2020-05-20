require 'rom'
require 'rom/sql/rake_task'

namespace :db do
  task :setup do
          # your ROM setup code
      #     # Usually something like this:
      #         # ROM::SQL::RakeSupport.env = ROM.container(...)
    config = ROM::Configuration.new(:sql, 'sqlite://board.db', {})
  end
end
