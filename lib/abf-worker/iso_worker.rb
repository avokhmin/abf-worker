require 'abf-worker/runners/iso'
require 'abf-worker/inspectors/live_inspector'

module AbfWorker
  class IsoWorker < BaseWorker
    @queue = :iso_worker

    class << self
      attr_accessor :runner

      protected

      # Initialize a new ISO worker.
      # @param [Hash] options The hash with options:
      # - [Integer] id The identifier of current build
      # - [String] srcpath The path for build scripts
      # - [String] params The params for running script
      # - [String] main_script The main script
      # - [String] time_living The max time for building (in minutes)
      # - [String] arch The arch of VM
      # - [String] distrib_type The type of product
      def initialize(options)
        @observer_queue = 'iso_worker_observer'
        @observer_class = 'AbfWorker::IsoWorkerObserver'
        super options
        @runner = Runners::Iso.new(self, options)
        initialize_live_inspector options['time_living']
      end

      def send_results
        update_build_status_on_abf({:results => @vm.upload_results_to_file_store})
      end

    end

    def self.logger
      @logger || init_logger("abfworker::iso-worker-#{@build_id}")
    end

    def self.perform(options)
      initialize options
      @vm.initialize_vagrant_env
      @vm.start_vm
      @runner.run_script
      @vm.rollback_and_halt_vm { send_results }
    rescue Resque::TermException
      @status = BUILD_FAILED if @status != BUILD_CANCELED
      @vm.clean { send_results }
    rescue => e
      @status = BUILD_FAILED if @status != BUILD_CANCELED
      print_error(e)
      @vm.rollback_and_halt_vm { send_results }
    end

  end

end