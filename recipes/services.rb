#
# Cookbook Name:: cookbook-openshift3
# Recipe:: services
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

service "#{node['cookbook-openshift3']['openshift_service_type']}-master"

service "#{node['cookbook-openshift3']['openshift_service_type']}-master-api" do
  retries 5
  retry_delay 5
end

service "#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers" do
  retries 5
  retry_delay 5
end

execute 'daemon-reload' do
  command 'systemctl daemon-reload'
  action :nothing
end

service 'httpd'

service 'docker'

service 'NetworkManager'

service 'openvswitch'

service 'haproxy'

service 'Restart Master' do
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-master"
  action :nothing
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master"
end

service 'Restart API' do
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-master-api"
  action :nothing
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master-api"
end

service 'Restart Controller' do
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-master-controllers"
  action :nothing
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-master-controllers"
end

service 'Restart Node' do
  service_name "#{node['cookbook-openshift3']['openshift_service_type']}-node"
  action :nothing
  only_if "systemctl is-active #{node['cookbook-openshift3']['openshift_service_type']}-node"
end

if node['cookbook-openshift3']['deploy_containerized']
  service 'etcd-service' do
    service_name 'etcd_container'
    action :nothing
  end
else
  service 'etcd-service' do
    service_name 'etcd'
    action :nothing
  end
end
