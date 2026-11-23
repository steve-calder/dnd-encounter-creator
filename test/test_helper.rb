ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/srd_fixture"
require_relative "test_helpers/search_index_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors, threshold: ENV.fetch("PARALLEL_THRESHOLD", 50).to_i)

    # Give each parallel worker its own database so one worker's cleanup can't
    # delete another worker's data.
    parallelize_setup do |worker|
      config = Mongoid::Config.clients[:default]
      config[:database] = "#{config[:database]}-#{worker}"
      Mongoid::Clients.disconnect
      Mongoid::Clients.clear
    end

    include SrdFixture

    # Clear documents, never drop collections (dropping would also drop search indexes).
    setup { Monster.delete_all }
  end
end
