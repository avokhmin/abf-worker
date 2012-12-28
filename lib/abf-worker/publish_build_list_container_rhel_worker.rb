require 'abf-worker/publish_build_list_container_base_worker'

module AbfWorker
  class PublishBuildListContainerRhelWorker < PublishBuildListContainerBaseWorker
    @queue = :publish_build_list_container_rhel_worker
  end

  class PublishBuildListContainerRhelWorkerDefault < PublishBuildListContainerRhelWorker
    @queue = :publish_build_list_container_rhel_worker_default
  end
end