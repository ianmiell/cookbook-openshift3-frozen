#
# Cookbook Name:: cookbook-openshift3
# Recipe:: upgrade_node36
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

# This must be run before any upgrade takes place.
# It creates the service signer certs (and any others) if they were not in
# existence previously.

log "Upgrade will be skipped. Could not find the flag: #{node['cookbook-openshift3']['control_upgrade_flag']}" do
  level :warn
  not_if { ::File.file?(node['cookbook-openshift3']['control_upgrade_flag']) }
end

if ::File.file?(node['cookbook-openshift3']['control_upgrade_flag'])

  node.force_override['cookbook-openshift3']['upgrade'] = true
  node.force_override['cookbook-openshift3']['ose_major_version'] = '3.6'
  node.force_override['cookbook-openshift3']['ose_version'] = '3.6.1-1.0.008f2d5'
  node.force_override['cookbook-openshift3']['openshift_docker_image_version'] = 'v3.6.1'
  node.force_override['yum']['main']['exclude'] = 'docker-1.13*'

  server_info = OpenShiftHelper::NodeHelper.new(node)
  is_node_server = server_info.on_node_server?

  if defined? node['cookbook-openshift3']['upgrade_repos']
    node.force_override['cookbook-openshift3']['yum_repositories'] = node['cookbook-openshift3']['upgrade_repos']
  end

  include_recipe 'yum::default'

  if is_node_server
    log 'Upgrade for NODE [STARTED]' do
      level :info
    end

    %w(excluder docker-excluder).each do |pkg|
      execute "Disable #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}" do
        command "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} enable"
      end
    end

    include_recipe 'cookbook-openshift3'
    include_recipe 'cookbook-openshift3::common'
    include_recipe 'cookbook-openshift3::node'

    log 'Node services' do
      level :info
      notifies :restart, "service[#{node['cookbook-openshift3']['openshift_service_type']}-node]", :immediately
      notifies :restart, 'service[openvswitch]', :immediately
      not_if { node['cookbook-openshift3']['deploy_containerized'] }
    end

    log 'Upgrade for NODE [COMPLETED]' do
      level :info
    end

    %w(excluder docker-excluder).each do |pkg|
      yum_package "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} = #{node['cookbook-openshift3']['ose_version'].to_s.split('-')[0]}"
      execute "Enable #{node['cookbook-openshift3']['openshift_service_type']}-#{pkg}" do
        command "#{node['cookbook-openshift3']['openshift_service_type']}-#{pkg} disable"
      end
    end
  end
end