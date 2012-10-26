require 'abf-worker/base_worker'
require 'abf-worker/runners/script'

module AbfWorker
  class ScriptWorker < BaseWorker
    extend Runners::Script

    @queue = :script_worker

    def self.initialize(build_id, os, arch, script_path)
      super(build_id, os, arch)
      @script_path = script_path
    end

    def self.perform(build_id, os, arch, script_path)
      initialize build_id, os, arch, script_path
      initialize_vagrant_env
      start_vm
      run_script
      rollback_and_halt_vm
    rescue Resque::TermException
      clean
    rescue Exception => e
      logger.error e.message
      rollback_and_halt_vm
    end

    def self.logger
      @logger || init_logger("abfworker::script-worker-#{@build_id}")
    end

  end
end