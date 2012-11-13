module AbfWorker
  module Runners
    module Vm
      VAGRANTFILES_FOLDER = File.dirname(__FILE__).to_s << '/../../../vagrantfiles'

      def initialize_vagrant_env
        vagrantfile = "#{VAGRANTFILES_FOLDER}/#{@vm_name}"
        first_run = false
        unless File.exist?(vagrantfile)
          begin
            file = File.open(vagrantfile, 'w')
            port = 2000 + (@build_id % 63000)
            str = "
              Vagrant::Config.run do |config|
                config.vm.share_folder('v-root', nil, nil)
                config.vm.define '#{@vm_name}' do |vm_config|
                  vm_config.vm.box = '#{@os}.#{@arch}'
                  vm_config.vm.forward_port 22, #{port}
                  vm_config.ssh.port = #{port}
                end
              end"
            file.write(str)
            first_run = true
          rescue IOError => e
            logger.error e.message
          ensure
            file.close unless file.nil?
          end
        end
        @vagrant_env = Vagrant::Environment.
          new(:vagrantfile_name => "vagrantfiles/#{@vm_name}")
        # Hook for fix:
        # ERROR warden: Error occurred: uninitialized constant VagrantPlugins::ProviderVirtualBox::Action::Customize::Errors
        # on vm_config.vm.customizations << ['modifyvm', :id, '--memory',  '#{memory}']
        # and config.vm.customize ['modifyvm', '#{@vm_name}', '--memory', '#{memory}']
        if first_run
          logger.info '==> Up VM at first time...'
          @vagrant_env.cli 'up', @vm_name
          logger.info '==> Set memory for VM...'
          # Halt, because: The machine 'abf-worker_...' is already locked for a session (or being unlocked)
          @vagrant_env.cli 'halt', @vm_name
          # memory = @arch == 'i586' ? 512 : 1024
          memory = @arch == 'i586' ? 4096 : 8192
          system "VBoxManage modifyvm #{@vagrant_env.vms.first[1].id} --memory #{memory}"
        end
      end



      def start_vm
        logger.info '==> Up VM...'
        @vagrant_env.cli 'up', @vm_name

        # VM should be exist before using sandbox
        logger.info '==> Enable save mode...'
        Sahara::Session.on(@vm_name, @vagrant_env)
      end

      def rollback_and_halt_vm
        # machine state should be (Running, Paused or Stuck)
        logger.info '==> Rollback activity'
        Sahara::Session.rollback(@vm_name, @vagrant_env)

        logger.info '==> Halt VM...'
        @vagrant_env.cli 'halt', @vm_name
        logger.info '==> Done.'
        yield if block_given?
      end

      def clean(destroy_all = false)
        files = []
        Dir.new(VAGRANTFILES_FOLDER).entries.each do |f|
          if File.file?(VAGRANTFILES_FOLDER + "/#{f}") &&
              (f =~ /#{@worker_id}/ || destroy_all) && !(f =~ /^\./)
            files << f
          end
        end
        files.each do |f|
          env = Vagrant::Environment.
            new(:vagrantfile_name => "vagrantfiles/#{f}", :ui => false)
          logger.info '==> Halt VM...'
          env.cli 'halt', '-f'

          logger.info '==> Disable save mode...'
          Sahara::Session.off(f, env)

          logger.info '==> Destroy VM...'
          env.cli 'destroy', '--force'

          File.delete(VAGRANTFILES_FOLDER + "/#{f}")
        end
        yield if block_given?
      end

    end
  end
end