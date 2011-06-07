#
# Cookbook Name:: gitolite
# Recipe:: default
#
# Copyright 2011, RocketLabs Development
#
# All rights reserved - Do Not Redistribute
#

package 'git'

bash 'install_gitolite' do
  cwd "/tmp"
  code <<-EOH
    git clone git://github.com/sitaramc/gitolite gitolite-source
    cd gitolite-source
    git checkout -t origin/pu
    mkdir -p /usr/local/share/gitolite/conf /usr/local/share/gitolite/hooks
    src/gl-system-install /usr/local/bin /usr/local/share/gitolite/conf /usr/local/share/gitolite/hooks
  EOH
  creates '/usr/local/bin/gl-setup'
end

gitolite_instances = node['gitolite']

gitolite_instances.each do |instance|
  username = instance['name']

  user username do
    comment "#{username} Gitolite User"
    home "/home/#{username}"
    shell "/bin/bash"
  end

  directory "/home/#{username}" do
    owner username
    action :create
  end

  admin_name = instance['admin']
  admin_ssh_key = data_bag_item('users',admin_name)['ssh_key']

  file "/tmp/gitolite-#{admin_name}.pub" do
    owner username
    content admin_ssh_key
  end

  template "/home/#{username}/.gitolite.rc" do
    owner username
    source "gitolite.rc.erb"
    action :create
  end

  execute "installing_gitolite_for" do
    user username
    command "/usr/local/bin/gl-setup /tmp/gitolite-#{admin_name}.pub"
    environment ({'HOME' => "/home/#{username}"})
  end
end




