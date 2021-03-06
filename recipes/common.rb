#
# Cookbook Name:: cookbook-openshift3
# Recipe:: common
#
# Copyright (c) 2015 The Authors, All Rights Reserved.

server_info = OpenShiftHelper::NodeHelper.new(node)
helper = OpenShiftHelper::UtilHelper
master_servers = server_info.master_servers
etcd_servers = server_info.etcd_servers
lb_servers = server_info.lb_servers
is_node_server = server_info.on_node_server?
certificate_server = server_info.certificate_server

include_recipe 'iptables::default'
include_recipe 'selinux_policy::default'

iptables_rule 'firewall_jump_rule' do
  action :enable
end

if !lb_servers.nil? && lb_servers.find { |lb| lb['fqdn'] == node['fqdn'] }
  package 'haproxy' do
    retries 3
  end

  node['cookbook-openshift3']['enabled_firewall_rules_lb'].each do |rule|
    iptables_rule rule do
      action :enable
    end
  end

  directory '/etc/systemd/system/haproxy.service.d' do
    recursive true
  end

  template '/etc/haproxy/haproxy.cfg' do
    source 'haproxy.conf.erb'
    variables(
      lazy do
        {
          master_servers: master_servers,
          maxconn: node['cookbook-openshift3']['lb_default_maxconn'].nil? ? '20000' : node['cookbook-openshift3']['lb_default_maxconn']
        }
      end
    )
    notifies :restart, 'service[haproxy]', :immediately
  end

  template '/etc/systemd/system/haproxy.service.d/limits.conf' do
    source 'haproxy.service.erb'
    variables nofile: node['cookbook-openshift3']['lb_limit_nofile'].nil? ? '100000' : node['cookbook-openshift3']['lb_limit_nofile']
    notifies :run, 'execute[daemon-reload]', :immediately
    notifies :restart, 'service[haproxy]', :immediately
  end
end

if node['cookbook-openshift3']['install_method'].eql? 'yum'
  node['cookbook-openshift3']['yum_repositories'].each do |repo|
    yum_repository repo['name'] do
      description "#{repo['name'].capitalize} aPaaS Repository"
      baseurl repo['baseurl']
      gpgcheck repo['gpgcheck'] if repo.key?(:gpgcheck) && !repo['gpgcheck'].nil?
      gpgkey repo['gpgkey'] if repo.key?(:gpgkey) && !repo['gpgkey'].nil?
      sslverify repo['sslverify'] if repo.key?(:sslverify) && !repo['sslverify'].nil?
      exclude repo['exclude'] if repo.key?(:exclude) && !repo['exclude'].nil?
      enabled repo['enabled'] if repo.key?(:enabled) && !repo['enabled'].nil?
      action :create
    end
  end
end

service 'firewalld' do
  action %i(stop disable)
end

package 'deltarpm' do
  retries 3
end

node['cookbook-openshift3']['core_packages'].each do |pkg|
  package pkg do
    retries 3
  end
end

if is_node_server || node['cookbook-openshift3']['deploy_containerized']
  yum_package 'docker' do
    action :upgrade if node['cookbook-openshift3']['upgrade']
    version node['cookbook-openshift3']['docker_version'] unless node['cookbook-openshift3']['docker_version'].nil?
    retries 3
    notifies :restart, 'service[docker]', :immediately if node['cookbook-openshift3']['upgrade']
  end

  bash "Configure Docker to use the default FS type for #{node['fqdn']}" do
    code <<-BASH
      correct_fs=$(df -T /var | egrep -o 'xfs|ext4')
      sed -i "s/xfs/$correct_fs/" /usr/bin/docker-storage-setup
    BASH
    not_if "grep $(df -T /var | egrep -o 'xfs|ext4') /usr/bin/docker-storage-setup"
    timeout 60
  end

  template '/etc/sysconfig/docker-storage-setup' do
    source 'docker-storage.erb'
  end

  template '/etc/sysconfig/docker' do
    source 'service_docker.sysconfig.erb'
    notifies :restart, 'service[docker]', :immediately
    notifies :enable, 'service[docker]', :immediately
  end
end

ruby_block 'Change HTTPD port xfer' do
  block do
    http_addresses = [etcd_servers, master_servers, [certificate_server]].each_with_object([]) do |candidate_servers, memo|
      this_server = candidate_servers.find { |server_candidate| server_candidate['fqdn'] == node['fqdn'] }
      memo << this_server['ipaddress'] if this_server
    end.sort.uniq

    openshift_settings = helper.new('/etc/httpd/conf/httpd.conf')
    openshift_settings.search_file_replace_line(
      /(^Listen.*?\n)+/m,
      http_addresses.map { |addr| "Listen #{addr}:#{node['cookbook-openshift3']['httpd_xfer_port']}\n" }.join
    )
    openshift_settings.write_file
  end
  action :nothing
  notifies :restart, 'service[httpd]', :immediately
end

include_recipe 'cookbook-openshift3::certificate_server' unless node['cookbook-openshift3']['upgrade']
include_recipe 'cookbook-openshift3::cloud_provider'
