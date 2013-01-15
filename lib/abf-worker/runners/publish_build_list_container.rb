require 'forwardable'
require 'abf-worker/models/repository'

module AbfWorker
  module Runners
    class PublishBuildListContainer
      extend Forwardable

      attr_accessor :script_runner,
                    :can_run

      def_delegators :@worker, :logger

      def initialize(worker, options)
        @worker         = worker
        @platform       = options['platform']
        @repository     = options['repository']
        @packages       = options['packages']
        @old_packages   = options['old_packages']
        @type           = options['type']
        @can_run        = true
      end

      def run_script
        if publish?
          @script_runner = Thread.new{ run_build_script }
        elsif cleanup?
          @script_runner = Thread.new{ run_cleanup_script }
        elsif resign?
          @script_runner = Thread.new{ run_resign_script }
        end
        @script_runner.join if @can_run
      end

      def rollback
        if publish?
          @worker.vm.rollback_vm
          run_build_script true
        end
      end

      private

      def cleanup?
        @type == 'cleanup'
      end

      def resign?
        @type == 'resign'
      end

      def publish?
        @type == 'publish'
      end

      def run_cleanup_script
        if @worker.vm.communicator.ready?
          init_packages_lists
          download_main_script

          command = base_command_for_run
          command << 'rebuild.sh'
          begin
            @worker.vm.execute_command command.join(' '), {:sudo => true}
          rescue => e
          end
        end
      end

      def run_resign_script
        if @worker.vm.communicator.ready?
          download_main_script
          init_gpg_keys

          command = base_command_for_run
          command << 'resign.sh'
          begin
            @worker.vm.execute_command command.join(' '), {:sudo => true}
          rescue => e
          end
        end
      end

      def run_build_script(rollback_activity = false)
        if @worker.vm.communicator.ready?
          init_packages_lists
          download_main_script
          init_gpg_keys unless rollback_activity
          logger.log "Run #{rollback_activity ? 'rollback activity ' : ''}script..."

          command = base_command_for_run
          command << (rollback_activity ? 'rollback.sh' : 'build.sh')
          critical_error = false
          begin
            @worker.vm.execute_command command.join(' '), {:sudo => true}
            logger.log 'Script done with exit_status = 0'
            @worker.status = AbfWorker::BaseWorker::BUILD_COMPLETED unless rollback_activity
          rescue AbfWorker::Exceptions::ScriptError => e
            logger.log "Script done with exit_status != 0. Error message: #{e.message}"
            @worker.status = AbfWorker::BaseWorker::BUILD_FAILED unless rollback_activity
          rescue => e
            @worker.print_error e
            @worker.status = AbfWorker::BaseWorker::BUILD_FAILED unless rollback_activity
            critical_error = true
          end
          # No logs on publishing build_list
          # save_results 
          rollback if critical_error && !rollback_activity
        end
      end

      def base_command_for_run
        command = []
        command << 'cd publish-build-list-script/;'
        command << "RELEASED=#{@platform['released']}"
        command << "REPOSITORY_NAME=#{@repository['name']}"
        command << "ARCH=#{@worker.vm.arch}"
        command << "TYPE=#{@worker.vm.os}"
        command << '/bin/bash'
        command
      end

      def init_packages_lists
        logger.log 'Initialize lists of new and old packages...'
        @worker.vm.execute_command 'mkdir container'
        add_packages_to_list @packages,     'new'
        add_packages_to_list @old_packages, 'old'
      end

      def add_packages_to_list(packages, list_prefix)
        commands = []
        (packages['sources'] || []).each{ |el| commands  << "echo #{el} >> container/#{list_prefix}.SRPMS.list" }
        (packages['binaries'] || {}).each{ |arch, list|
          list.each{ |el| commands  << "echo #{el} >> container/#{list_prefix}.#{arch}.list" }
        }
        commands.each{ |c| @worker.vm.execute_command(c) }
      end

      def download_main_script
        commands = []
        commands << "curl -O -L #{APP_CONFIG['scripts']['publish_build_list']}"
        file_name = 'avokhmin-publish-build-list-script-master.tar.gz'
        commands << "tar -xzf #{file_name}"
        folder_name = file_name.gsub /\.tar\.gz$/, ''
        commands << "mv #{folder_name} publish-build-list-script"
        commands << "rm -rf #{file_name}"

        commands.each{ |c| @worker.vm.execute_command(c) }
      end

      def init_gpg_keys
        return true # TODO: Remove this line when API will be done.
        repository = AbfWorker::Models::Repository.find_by_id(options['repository']['id'])
        return if repository.nil? || repository.key_pair.secret.empty?

        @worker.vm.execute_command 'mkdir -m 700 /home/vagrant/.gnupg'
        dir = Dir.mktmpdir('keys-', "#{@worker.tmp_dir}")
        begin
          port = @worker.vm.get_vm.config.ssh.port
          [:pubring, :secring].each do |key|
            open("#{dir}/#{key}.txt", "w") { |f|
              f.write repository.key_pair.send(key == :secring ? :secret : :public)
            }
            system "gpg --homedir #{dir} --dearmor < #{dir}/#{key}.txt > #{dir}/#{key}.gpg"
            system "scp -o 'StrictHostKeyChecking no' -i keys/vagrant -P #{port} #{dir}/#{key}.gpg vagrant@127.0.0.1:/home/vagrant/.gnupg/#{key}.gpg"
          end
        ensure
          # remove the directory.
          FileUtils.remove_entry_secure dir
        end
      end

    end
  end
end